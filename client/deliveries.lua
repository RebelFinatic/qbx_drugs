local config = require 'config.client'
local sharedConfig = require 'config.shared'

---@diagnostic disable-next-line: param-type-mismatch
AddStateBagChangeHandler('isLoggedIn', nil, function(_, _, value)
    if value then
        InitZones()
    else
        if not config.useTarget then
            local dealerZones = LocalPlayer.state.dealerZones
            if dealerZones then
                for _, zone in pairs(dealerZones) do
                    zone:remove()
                end
                LocalPlayer.state.dealerZones = nil
            end
        end
        -- Clean up delivery zone
        if LocalPlayer.state.drugDeliveryZone then
            if LocalPlayer.state.drugDeliveryZone.remove then
                LocalPlayer.state.drugDeliveryZone:remove()
            elseif LocalPlayer.state.drugDeliveryZone.destroy then
                LocalPlayer.state.drugDeliveryZone:destroy()
            end
            LocalPlayer.state.drugDeliveryZone = nil
        end
    end
end)

local function getClosestDealer()
    local pCoords = GetEntityCoords(cache.ped)
    for k, v in pairs(sharedConfig.dealers) do
        local dealerCoords = vector3(v.coords.x, v.coords.y, v.coords.z)
        if #(pCoords - dealerCoords) < 2 then
            LocalPlayer.state.currentDealer = k
            break
        end
    end
end

local function openDealerShop()
    getClosestDealer()
    local dealerName = sharedConfig.dealers[LocalPlayer.state.currentDealer].name
    exports.ox_inventory:openInventory('shop', { type = 'Dealer_' .. dealerName })
end

local function knockDoorAnim(home)
    local knockAnimLib = 'timetable@jimmy@doorknock@'
    local knockAnim = 'knockdoor_idle'

    if home then
        TriggerServerEvent('InteractSound_SV:PlayOnSource', 'knock_door', 0.2)
        Wait(100)
        lib.playAnim(cache.ped, knockAnimLib, knockAnim, 3.0, 3.0, -1, 1, 0, false, false, false )
        Wait(3500)
        lib.playAnim(cache.ped, knockAnimLib, 'exit', 3.0, 3.0, -1, 1, 0, false, false, false)
        Wait(1000)
        LocalPlayer.state.dealerIsHome = true
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = true,
            args = {
                locale('info.dealer_name', sharedConfig.dealers[LocalPlayer.state.currentDealer].name),
                locale('info.fred_knock_message', QBX.PlayerData.charinfo.firstname)
            }
        })
        lib.showTextUI(locale('info.other_dealers_button'), { position = 'left-center' })
        AwaitingInput()
    else
        TriggerServerEvent('InteractSound_SV:PlayOnSource', 'knock_door', 0.2)
        Wait(100)
        lib.playAnim(cache.ped, knockAnimLib, knockAnim, 3.0, 3.0, -1, 1, 0, false, false, false )
        Wait(3500)
        lib.playAnim(cache.ped, knockAnimLib, 'exit', 3.0, 3.0, -1, 1, 0, false, false, false)
        Wait(1000)
        exports.qbx_core:Notify(locale('info.no_one_home'), 'error')
    end
end

local function knockDealerDoor()
    getClosestDealer()
    local hours = GetClockHours()
    local min = sharedConfig.dealers[LocalPlayer.state.currentDealer].time.min
    local max = sharedConfig.dealers[LocalPlayer.state.currentDealer].time.max
    if max < min then
        if hours <= max then
            knockDoorAnim(true)
        elseif hours >= min then
            knockDoorAnim(true)
        else
            knockDoorAnim(false)
        end
    else
        if hours >= min and hours <= max then
            knockDoorAnim(true)
        else
            knockDoorAnim(false)
        end
    end
end

local function randomDeliveryItemOnRep()
    local myRep = QBX.PlayerData.metadata.dealerrep
    local availableItems = {}
    for k in pairs(sharedConfig.deliveryItems) do
        if sharedConfig.deliveryItems[k].minrep <= myRep then
            availableItems[#availableItems+1] = k
        end
    end
    return availableItems[math.random(1, #availableItems)]
end

local function requestDelivery()
    if not LocalPlayer.state.waitingDelivery then
        getClosestDealer()
        exports.qbx_core:Notify(locale('info.sending_delivery_email'), 'success')
        TriggerServerEvent('qbx_drugs:server:requestDelivery', LocalPlayer.state.currentDealer)
    else
        exports.qbx_core:Notify(locale('error.pending_delivery'), 'error')
    end
end

RegisterNetEvent('qbx_drugs:client:startDelivery', function(data)
    LocalPlayer.state.waitingDelivery = data

    SetTimeout(2000, function()
        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender = sharedConfig.dealers[data.dealer].name,
            subject = 'Delivery Location',
            message = locale('info.delivery_info_email', data.amount, data.itemLabel),
            button = {
                enabled = true,
                buttonEvent = 'qbx_drugs:client:setLocation',
                buttonData = data
            }
        })
    end)
end)

local function deliveryTimer()
    CreateThread(function()
        local timeout = LocalPlayer.state.deliveryTimeout
        while timeout - 1 > 0 do
            timeout = timeout - 1
            LocalPlayer.state.deliveryTimeout = timeout
            Wait(1000)
        end
        LocalPlayer.state.deliveryTimeout = 0
    end)
end

local function deliverStuff()
    local deliveryTimeout = LocalPlayer.state.deliveryTimeout
    local activeDelivery = LocalPlayer.state.activeDelivery
    local drugDeliveryZone = LocalPlayer.state.drugDeliveryZone

    if deliveryTimeout > 0 then
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
            LocalPlayer.state.activeDelivery = nil
            if config.useTarget then
                exports.ox_target:removeZone('drugDeliveryZone')
            else
                if drugDeliveryZone then
                    drugDeliveryZone:destroy()
                    LocalPlayer.state.drugDeliveryZone = nil
                end
            end
        else
            ClearPedTasks(cache.ped)
        end
    else
        TriggerServerEvent('qbx_drugs:server:successDelivery', activeDelivery, false)
    end
    LocalPlayer.state.deliveryTimeout = 0
end

local function setMapBlip(x, y)
    SetNewWaypoint(x, y)
    exports.qbx_core:Notify(locale('success.route_has_been_set'), 'success');
end

-- PolyZone specific functions
function AwaitingInput()
    if LocalPlayer.state.waitingKeyPress then return end -- Prevent multiple threads
    CreateThread(function()
        LocalPlayer.state.waitingKeyPress = true
        while LocalPlayer.state.waitingKeyPress do
            if not LocalPlayer.state.dealerIsHome then
                if IsControlJustPressed(0, 38) then
                    knockDealerDoor()
                end
            elseif LocalPlayer.state.dealerIsHome then
                if IsControlJustPressed(0, 38) then
                    openDealerShop()
                    -- Don't exit loop, just wait for next input
                end
                if IsControlJustPressed(0, 47) then
                    requestDelivery()
                    LocalPlayer.state.dealerIsHome = false
                    -- Update text UI to show knock button again
                    lib.showTextUI(locale('info.knock_button'), { position = 'left-center' })
                end
            end
            Wait(0)
        end
    end)
end

function InitZones()
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
                        onSelect = function()
                            requestDelivery()
                        end,
                        canInteract = function()
                            getClosestDealer()
                            local hours = GetClockHours()
                            local min = sharedConfig.dealers[LocalPlayer.state.currentDealer].time.min
                            local max = sharedConfig.dealers[LocalPlayer.state.currentDealer].time.max
                            if max < min then
                                return (hours <= max or hours >= min) and not LocalPlayer.state.waitingDelivery
                            else
                                return (hours >= min and hours <= max) and not LocalPlayer.state.waitingDelivery
                            end
                        end,
                        distance = 1.5
                    },
                    {
                        name = 'open_shop',
                        icon = 'fas fa-user-secret',
                        label = locale('info.target_openshop'),
                        onSelect = function()
                            openDealerShop()
                        end,
                        canInteract = function()
                            getClosestDealer()
                            local hours = GetClockHours()
                            local min = sharedConfig.dealers[LocalPlayer.state.currentDealer].time.min
                            local max = sharedConfig.dealers[LocalPlayer.state.currentDealer].time.max
                            if max < min then
                                return hours <= max or hours >= min
                            else
                                return hours >= min and hours <= max
                            end
                        end,
                        distance = 1.5
                    }
                }
            })
        end
    else
        -- ox_lib zones for non-target mode
        local dealerZones = {}

        for k, v in pairs(sharedConfig.dealers) do
            print('[qbx_drugs] Creating lib zone for dealer:', k)

            local zone = lib.zones.box({
                coords = vec3(v.coords.x, v.coords.y, v.coords.z),
                size = vec3(1.5, 1.5, 2.0),
                rotation = v.heading or 0.0,
                debug = false,
                onEnter = function()
                    getClosestDealer()
                    if not LocalPlayer.state.dealerIsHome then
                        lib.showTextUI(locale('info.knock_button'), { position = 'left-center' })
                        AwaitingInput()
                    elseif LocalPlayer.state.dealerIsHome then
                        lib.showTextUI(locale('info.other_dealers_button'), { position = 'left-center' })
                        AwaitingInput()
                    end
                end,
                onExit = function()
                    LocalPlayer.state.waitingKeyPress = false
                    lib.hideTextUI()
                end
            })
            dealerZones[#dealerZones + 1] = zone
        end

        LocalPlayer.state.dealerZones = dealerZones
        return
    end
end

-- Events

RegisterNetEvent('qbx_drugs:client:setLocation', function(locationData)
    local activeDelivery = LocalPlayer.state.activeDelivery
    local waitingDelivery = LocalPlayer.state.waitingDelivery

    if activeDelivery then
        setMapBlip(activeDelivery.coords.x, activeDelivery.coords.y)
        exports.qbx_core:Notify(locale('error.pending_delivery'), 'error')
        return
    end
    LocalPlayer.state.activeDelivery = locationData
    LocalPlayer.state.deliveryTimeout = 300
    deliveryTimer()
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
                        LocalPlayer.state.waitingDelivery = nil
                    end,
                    canInteract = function(_, distance)
                        return LocalPlayer.state.waitingDelivery and distance <= 2.5
                    end
                }
            }
        })
    else
        local inDeliveryZone = false
        local drugDeliveryZone = lib.zones.box({
            coords = vec3(locationData.coords.x, locationData.coords.y, locationData.coords.z),
            size = vec3(1.5, 1.5, 2.0),
            rotation = 0.0,
            debug = false,
            onEnter = function()
                inDeliveryZone = true
                LocalPlayer.state.drugDeliveryZone = drugDeliveryZone
                lib.showTextUI(locale('info.deliver_items_button', locationData.amount, exports.ox_inventory:Items()[locationData.itemData.item].label), {
                    position = 'left-center'
                })
                CreateThread(function()
                    while inDeliveryZone do
                        if IsControlJustPressed(0, 38) then
                            deliverStuff()
                            LocalPlayer.state.waitingDelivery = nil
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
    if type == 'perfect' then
        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender = sharedConfig.dealers[deliveryData.dealer].name,
            subject = 'Delivery',
            message = locale('info.perfect_delivery', sharedConfig.dealers[deliveryData.dealer].name)
        })
    elseif type == 'bad' then
        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender = sharedConfig.dealers[deliveryData.dealer].name,
            subject = 'Delivery',
            message = locale('info.bad_delivery')
        })
    elseif type == 'late' then
        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender = sharedConfig.dealers[deliveryData.dealer].name,
            subject = 'Delivery',
            message = locale('info.late_delivery')
        })
    end
end)