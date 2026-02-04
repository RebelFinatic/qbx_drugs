local config = require 'config.client'
local sharedConfig = require 'config.shared'

-- Local state
local dealerZones = {}
local drugDeliveryZone = nil
local currentDealer = nil
local waitingDelivery = nil
local activeDelivery = nil
local deliveryExpiryTime = 0
local dealerIsHome = false
local waitingKeyPress = false
local inDeliveryZone = false

---@param x number
---@param y number
local function setMapBlip(x, y)
    SetNewWaypoint(x, y)
    exports.qbx_core:Notify(locale('success.route_has_been_set'), 'success')
end

local function cleanupState()
    if dealerZones then
        for _, zone in pairs(dealerZones) do
            if zone.remove then zone:remove() end
        end
        dealerZones = {}
    end

    if drugDeliveryZone then
        if drugDeliveryZone.remove then drugDeliveryZone:remove()
        elseif drugDeliveryZone.destroy then drugDeliveryZone:destroy() end
        drugDeliveryZone = nil
    end

    currentDealer = nil
    waitingDelivery = nil
    activeDelivery = nil
    deliveryExpiryTime = 0
    dealerIsHome = false
    waitingKeyPress = false
    inDeliveryZone = false
end

local function getClosestDealer()
    local pCoords = GetEntityCoords(cache.ped)
    for k, v in pairs(sharedConfig.dealers) do
        local dealerCoords = vector3(v.coords.x, v.coords.y, v.coords.z)
        if #(pCoords - dealerCoords) < 2 then
            currentDealer = k
            break
        end
    end
end

local function openDealerShop()
    getClosestDealer()
    if not currentDealer then return end
    local dealerName = sharedConfig.dealers[currentDealer].name
    exports.ox_inventory:openInventory('shop', { type = 'Dealer_' .. dealerName })
end

local function requestDelivery()
    if not waitingDelivery then
        getClosestDealer()
        if config.usePhone then
            exports.qbx_core:Notify(locale('info.sending_delivery_email'), 'success')
        else
            exports.qbx_core:Notify(locale('info.requesting_delivery'), 'success')
        end
        TriggerServerEvent('qbx_drugs:server:requestDelivery', currentDealer)
    else
        exports.qbx_core:Notify(locale('error.pending_delivery'), 'error')
    end
end

local function knockDoorAnim(home)
    local knockAnimLib = 'timetable@jimmy@doorknock@'
    local knockAnim = 'knockdoor_idle'

    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'knock_door', 0.2)
    Wait(100)
    lib.playAnim(cache.ped, knockAnimLib, knockAnim, 3.0, 3.0, -1, 1, 0, false, false, false )
    Wait(3500)
    lib.playAnim(cache.ped, knockAnimLib, 'exit', 3.0, 3.0, -1, 1, 0, false, false, false)
    Wait(1000)

    if home then
        dealerIsHome = true
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = true,
            args = {
                locale('info.dealer_name', sharedConfig.dealers[currentDealer].name),
                locale('info.fred_knock_message', QBX.PlayerData.charinfo.firstname)
            }
        })
        lib.showTextUI(locale('info.other_dealers_button'), { position = 'left-center' })
    else
        exports.qbx_core:Notify(locale('info.no_one_home'), 'error')
    end
end

local function knockDealerDoor()
    getClosestDealer()
    if not currentDealer then return end

    local hours = GetClockHours()
    local min = sharedConfig.dealers[currentDealer].time.min
    local max = sharedConfig.dealers[currentDealer].time.max

    local isOpen = false
    if max < min then
         isOpen = (hours <= max or hours >= min)
    else
         isOpen = (hours >= min and hours <= max)
    end

    knockDoorAnim(isOpen)
end

-- PolyZone Input Loop
local function startInputLoop()
    if waitingKeyPress then return end
    waitingKeyPress = true

    CreateThread(function()
        while waitingKeyPress do
            if IsControlJustPressed(0, 38) then -- E
                if not dealerIsHome then
                    knockDealerDoor()
                else
                    openDealerShop()
                end
            end

            if dealerIsHome and IsControlJustPressed(0, 47) then -- G
                requestDelivery()
                dealerIsHome = false
                lib.showTextUI(locale('info.knock_button'), { position = 'left-center' })
            end

            Wait(0)
        end
    end)
end

local function deliverStuff()
    if not activeDelivery then return end

    local isLate = GetGameTimer() > deliveryExpiryTime

    if not isLate then
        Wait(500)
        TriggerEvent('animations:client:EmoteCommandStart', {'bumbin'})
        TriggerServerEvent('qbx_drugs:server:randomPoliceAlert')

        if lib.progressCircle({
            label = locale('info.delivering_products'),
            duration = 3500,
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = { car = true, move = true, combat = true }
        }) then
            TriggerServerEvent('qbx_drugs:server:successDelivery', activeDelivery, true)
            activeDelivery = nil
            deliveryExpiryTime = 0

            if config.useTarget then
                exports.ox_target:removeZone('drugDeliveryZone')
            else
                if drugDeliveryZone then
                    drugDeliveryZone:remove()
                    drugDeliveryZone = nil
                    inDeliveryZone = false
                    lib.hideTextUI()
                end
            end
        else
            ClearPedTasks(cache.ped)
        end
    else
        TriggerServerEvent('qbx_drugs:server:successDelivery', activeDelivery, false)
        activeDelivery = nil
        deliveryExpiryTime = 0
    end
end

local function initZones()
    print('[qbx_drugs] Initializing zones... useTarget:', config.useTarget)
    if config.useTarget then
        for k, v in pairs(sharedConfig.dealers) do
             exports.ox_target:addBoxZone({
                name = 'dealer_'..k,
                coords = vec3(v.coords.x, v.coords.y, v.coords.z),
                size = vec3(1.5, 1.5, 2.0),
                rotation = v.heading or 0.0,
                debug = false,
                options = {
                    {
                        name = 'request_delivery',
                        icon = 'fas fa-user-secret',
                        label = locale('info.target_request'),
                        onSelect = function() requestDelivery() end,
                        canInteract = function()
                            getClosestDealer()
                            if not currentDealer then return false end

                            local hours = GetClockHours()
                            local min = sharedConfig.dealers[currentDealer].time.min
                            local max = sharedConfig.dealers[currentDealer].time.max

                            local isOpen = false
                            if max < min then
                                isOpen = (hours <= max or hours >= min)
                            else
                                isOpen = (hours >= min and hours <= max)
                            end

                            return isOpen and not waitingDelivery
                        end,
                        distance = 1.5
                    },
                    {
                        name = 'open_shop',
                        icon = 'fas fa-user-secret',
                        label = locale('info.target_openshop'),
                        onSelect = function() openDealerShop() end,
                        canInteract = function()
                            getClosestDealer()
                            if not currentDealer then return false end

                            local hours = GetClockHours()
                            local min = sharedConfig.dealers[currentDealer].time.min
                            local max = sharedConfig.dealers[currentDealer].time.max

                            local isOpen = false
                            if max < min then
                                isOpen = (hours <= max or hours >= min)
                            else
                                isOpen = (hours >= min and hours <= max)
                            end
                            return isOpen
                        end,
                        distance = 1.5
                    }
                }
            })
        end
    else
        for k, v in pairs(sharedConfig.dealers) do
            local zone = lib.zones.box({
                coords = vec3(v.coords.x, v.coords.y, v.coords.z),
                size = vec3(1.5, 1.5, 2.0),
                rotation = v.heading or 0.0,
                debug = false,
                onEnter = function()
                    getClosestDealer()
                    if not dealerIsHome then
                        lib.showTextUI(locale('info.knock_button'), { position = 'left-center' })
                        startInputLoop()
                    else
                        lib.showTextUI(locale('info.other_dealers_button'), { position = 'left-center' })
                        startInputLoop()
                    end
                end,
                onExit = function()
                    waitingKeyPress = false
                    lib.hideTextUI()
                end
            })
            dealerZones[#dealerZones + 1] = zone
        end
    end
end

-- Events

AddStateBagChangeHandler('isLoggedIn', nil, function(_, _, value)
    if value then
        initZones()
    else
        cleanupState()
    end
end)

RegisterNetEvent('qbx_drugs:client:startDelivery', function(data)
    waitingDelivery = data
    SetTimeout(2000, function()
        sendNotification({
            sender = sharedConfig.dealers[data.dealer].name,
            subject = 'Delivery Location',
            message = locale('info.delivery_info_email', data.amount, data.itemLabel),
            button = {
                enabled = true,
                buttonEvent = 'qbx_drugs:client:setLocation',
                buttonData = data
            },
            -- Extra data for non-phone fallback
            isLocationEmail = true,
            locationData = data
        })
    end)
end)

RegisterNetEvent('qbx_drugs:client:setLocation', function(locationData)
    if activeDelivery then
        setMapBlip(activeDelivery.coords.x, activeDelivery.coords.y)
        exports.qbx_core:Notify(locale('error.pending_delivery'), 'error')
        return
    end

    activeDelivery = locationData
    deliveryExpiryTime = GetGameTimer() + (300 * 1000) -- 5 minutes

    setMapBlip(locationData.coords.x, locationData.coords.y)

    if config.useTarget then
        exports.ox_target:addBoxZone({
            name = 'drugDeliveryZone',
            coords = vec3(locationData.coords.x, locationData.coords.y, locationData.coords.z),
            size = vec3(1.5, 1.5, 2.0),
            rotation = 0.0,
            debug = false,
            options = {
                {
                    icon = 'fas fa-user-secret',
                    label = locale('info.target_deliver'),
                    onSelect = function()
                        deliverStuff()
                        waitingDelivery = nil
                    end,
                    canInteract = function(_, distance)
                        return waitingDelivery and distance <= 2.5
                    end
                }
            }
        })
    else
        inDeliveryZone = false
        drugDeliveryZone = lib.zones.box({
            coords = vec3(locationData.coords.x, locationData.coords.y, locationData.coords.z),
            size = vec3(1.5, 1.5, 2.0),
            rotation = 0.0,
            debug = false,
            onEnter = function()
                inDeliveryZone = true
                drugDeliveryZone = drugDeliveryZone -- redundant but keeps reference clear
                lib.showTextUI(locale('info.deliver_items_button', locationData.amount, locationData.itemLabel), {
                    position = 'left-center'
                })

                CreateThread(function()
                    while inDeliveryZone do
                        if IsControlJustPressed(0, 38) then
                            deliverStuff()
                            waitingDelivery = nil
                            break
                        end
                        Wait(0)
                    end
                end)
            end,
            onExit = function()
                inDeliveryZone = false
                lib.hideTextUI()
            end
        })
    end
end)

RegisterNetEvent('qbx_drugs:client:sendDeliveryMail', function(type, deliveryData)
    local senderName = sharedConfig.dealers[deliveryData.dealer].name
    local subject = 'Delivery'
    local message = ''

    if type == 'perfect' then
        message = locale('info.perfect_delivery', senderName)
    elseif type == 'bad' then
        message = locale('info.bad_delivery')
    elseif type == 'late' then
        message = locale('info.late_delivery')
    end

    TriggerServerEvent('qb-phone:server:sendNewMail', {
        sender = senderName,
        subject = subject,
        message = message
    })
end)

---@param data table
function sendNotification(data)
    if config.usePhone then
        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender = data.sender,
            subject = data.subject,
            message = data.message,
            button = data.button
        })
    else
        -- Fallback for no phone
        if data.isLocationEmail and data.locationData then
            -- Auto-set location since we can't click the email button
            TriggerEvent('qbx_drugs:client:setLocation', data.locationData)
            lib.notify({
                title = data.subject,
                description = data.message,
                type = 'inform',
                duration = 10000,
                icon = 'envelope'
            })
        else
            lib.notify({
                title = data.subject .. ' - ' .. data.sender,
                description = data.message,
                type = 'inform',
                duration = 5000,
                icon = 'envelope'
            })
        end
    end
end