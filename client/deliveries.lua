local config = require 'config.client'
local sharedConfig = require 'config.shared'
local currentDealer = nil
local dealerIsHome = false
local waitingDelivery = nil
local activeDelivery = nil
local deliveryTimeout = 0
local waitingKeyPress = false
local dealerCombo = false
local drugDeliveryZone

---@diagnostic disable-next-line: param-type-mismatch
AddStateBagChangeHandler('isLoggedIn', nil, function(_, _, value)
    if value then
        sharedConfig.dealers = lib.callback.await('qbx_drugs:server:RequestConfig', false)
        InitZones()
    else
        if not config.useTarget and dealerCombo then dealerCombo:destroy() end
    end
end)

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

---@todo Move to ox_inventory Shop
local function openDealerShop()
    getClosestDealer()
    local repItems = {}
    repItems.label = sharedConfig.dealers[currentDealer].name
    repItems.items = {}
    repItems.slots = 30
    for k, _ in pairs(sharedConfig.dealers[currentDealer].products) do
        if QBX.PlayerData.metadata.dealerrep >= sharedConfig.dealers[currentDealer].products[k].minrep then
            repItems.items[k] = sharedConfig.dealers[currentDealer].products[k]
        end
    end
    TriggerServerEvent('inventory:server:OpenInventory', 'shop', 'Dealer_'..sharedConfig.dealers[currentDealer].name, repItems)
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
    local min = sharedConfig.dealers[currentDealer].time.min
    local max = sharedConfig.dealers[currentDealer].time.max
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
    if not waitingDelivery then
        getClosestDealer()
        local location = math.random(1, #config.deliveryLocations)
        local amount = math.random(1, 3)
        local item = randomDeliveryItemOnRep()

        waitingDelivery = {
            coords = config.deliveryLocations[location].coords,
            locationLabel = config.deliveryLocations[location].label,
            amount = amount,
            dealer = currentDealer,
            itemData = sharedConfig.deliveryItems[item],
            item = item
        }

        exports.qbx_core:Notify(locale('info.sending_delivery_email'), 'success')
        TriggerServerEvent('qbx_drugs:server:giveDeliveryItems', waitingDelivery)
        SetTimeout(2000, function()
            TriggerServerEvent('qb-phone:server:sendNewMail', {
                sender = sharedConfig.dealers[currentDealer].name,
                subject = 'Delivery Location',
                message = locale('info.delivery_info_email', amount, exports.ox_inventory:Items()[waitingDelivery.itemData.item].label),
                button = {
                    enabled = true,
                    buttonEvent = 'qbx_drugs:client:setLocation',
                    buttonData = waitingDelivery
                }
            })
        end)
    else
        exports.qbx_core:Notify(locale('error.pending_delivery'), 'error')
    end
end

local function deliveryTimer()
    CreateThread(function()
        while deliveryTimeout - 1 > 0 do
            deliveryTimeout -= 1
            Wait(1000)
        end
        deliveryTimeout = 0
    end)
end

local function deliverStuff()
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
            activeDelivery = nil
            if config.useTarget then
                exports.ox_target:removeZone('drugDeliveryZone')
            else
                drugDeliveryZone:destroy()
            end
        else
            ClearPedTasks(cache.ped)
        end
    else
        TriggerServerEvent('qbx_drugs:server:successDelivery', activeDelivery, false)
    end
    deliveryTimeout = 0
end

local function setMapBlip(x, y)
    SetNewWaypoint(x, y)
    exports.qbx_core:Notify(locale('success.route_has_been_set'), 'success');
end

-- PolyZone specific functions

function AwaitingInput()
    CreateThread(function()
        waitingKeyPress = true
        while waitingKeyPress do
            if not dealerIsHome then
                if IsControlPressed(0, 38) then
                    knockDealerDoor()
                end
            elseif dealerIsHome then
                if IsControlJustPressed(0, 38) then
                    openDealerShop()
                    waitingKeyPress = false
                end
                if IsControlJustPressed(0, 47) then
                    if waitingDelivery then
                        waitingKeyPress = false
                    end
                    requestDelivery()
                    dealerIsHome = false
                    waitingKeyPress = false
                end
            end
            Wait(0)
        end
    end)
end

function InitZones()
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
                            local min = sharedConfig.dealers[currentDealer].time.min
                            local max = sharedConfig.dealers[currentDealer].time.max
                            if max < min then
                                return (hours <= max or hours >= min) and not waitingDelivery
                            else
                                return (hours >= min and hours <= max) and not waitingDelivery
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
                            local min = sharedConfig.dealers[currentDealer].time.min
                            local max = sharedConfig.dealers[currentDealer].time.max
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
        ---@TODO Move to ox_lib Zoning

        --[[ local dealerPoly = {}
        for k, v in pairs(sharedConfig.dealers) do
            dealerPoly[#dealerPoly+1] = BoxZone:Create(vector3(v.coords.x, v.coords.y, v.coords.z), 1.5, 1.5, {
                heading = -20,
                name='dealer_'..k,
                debugPoly = false,
                minZ = v.coords.z - 1,
                maxZ = v.coords.z + 1,
            })
        end

        if table.type(dealerPoly) == 'empty' then return end

        dealerCombo = ComboZone:Create(dealerPoly, {name = 'dealerPoly'})
        dealerCombo:onPlayerInOut(function(isPointInside)
            if isPointInside then
                if not dealerIsHome then
                    lib.showTextUI(locale('info.knock_button'), { position = 'left-center' })
                    AwaitingInput()
                elseif dealerIsHome then
                    lib.showTextUI(locale('info.other_dealers_button'), { position = 'left-center' })
                    AwaitingInput()
                end
            else
                waitingKeyPress = false
                lib.hideTextUI()
            end
        end) ]]--

        return
    end
end

-- Events

RegisterNetEvent('qbx_drugs:client:RefreshDealers', function(DealerData)
    if not config.useTarget and dealerCombo then dealerCombo:destroy() end
    sharedConfig.dealers = DealerData
    Wait(1000)
    InitZones()
end)

RegisterNetEvent('qbx_drugs:client:updateDealerItems', function(itemData, amount)
    TriggerServerEvent('qbx_drugs:server:updateDealerItems', itemData, amount, currentDealer)
end)

RegisterNetEvent('qbx_drugs:client:setDealerItems', function(itemData, amount, dealer)
    sharedConfig.dealers[dealer].products[itemData.slot].amount = sharedConfig.dealers[dealer].products[itemData.slot].amount - amount
end)

RegisterNetEvent('qbx_drugs:client:setLocation', function(locationData)
    if activeDelivery then
        setMapBlip(activeDelivery.coords.x, activeDelivery.coords.y)
        exports.qbx_core:Notify(locale('error.pending_delivery'), 'error')
        return
    end
    activeDelivery = locationData
    deliveryTimeout = 300
    deliveryTimer()
    setMapBlip(activeDelivery.coords.x, activeDelivery.coords.y)
    if config.useTarget then
        exports.ox_target:addBoxZone({
            name = 'drugDeliveryZone',
            coords = vec3(activeDelivery.coords.x, activeDelivery.coords.y, activeDelivery.coords.z),
            size = vec3(1.5, 1.5, 2.0),
            rotation = 0.0,
            debug = true,
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
        local inDeliveryZone = false
        drugDeliveryZone = lib.zones.box({
            coords = vec3(activeDelivery.coords.xyz),
            size = vec3(1.5, 1.5, 2.0),
            rotation = 0.0,
            debug = false,
            onEnter = function()
                inDeliveryZone = true
                lib.showTextUI(locale('info.deliver_items_button', activeDelivery.amount, exports.ox_inventory:Items()[activeDelivery.itemData.item].label), {
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