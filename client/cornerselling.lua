local config = require 'config.client'

-- Local state variables (not networked)
local lastPeds = {}
local isSelling = false
local hasTarget = false
local currentOffer = nil
local stealingPed = nil
local stealData = {}
local zoneMade = false
local textDrawn = false
local sellingPoint = nil

---@param ped number
local function addToLastPed(ped)
    lastPeds[#lastPeds + 1] = ped
end

local function stopSelling()
    if sellingPoint then
        sellingPoint:remove()
        sellingPoint = nil
    end

    isSelling = false
    hasTarget = false
    currentOffer = nil
    stealingPed = nil
    stealData = {}
    zoneMade = false
    textDrawn = false
    lastPeds = {}
end



local function handleRobbery(ped)
    if not stealingPed then return end

    if config.useTarget then
        local targetPedNetId = NetworkGetNetworkIdFromEntity(stealingPed)
        exports.ox_target:addEntity(targetPedNetId, {
            {
                name = 'stealingped',
                icon = 'fas fa-magnifying-glass',
                label = locale('info.search_ped'),
                onSelect = function()
                    if lib.progressCircle({
                        duration = 2000,
                        position = 'bottom',
                        useWhileDead = false,
                        canCancel = true,
                        disable = { car = true, move = true },
                        anim = { dict = 'pickup_object', clip = 'pickup_low' }
                    }) then
                        TriggerServerEvent('qbx_drugs:server:giveStealItems')
                        TriggerEvent('inventory:client:ItemBox', exports.ox_inventory:Items()[stealData.item], 'add')
                        if stealingPed then
                            exports.ox_target:removeEntity(targetPedNetId, 'stealingped')
                        end
                        stealingPed = nil
                        stealData = {}
                    end
                end,
                canInteract = function(entity)
                    return IsEntityDead(entity)
                end
            }
        })
    end

    -- Monitor robbery ped distance/state
    CreateThread(function()
        while stealingPed do
            if not DoesEntityExist(stealingPed) then
                stealingPed = nil
                break
            end

            local pos = GetEntityCoords(cache.ped)
            local pedPos = GetEntityCoords(stealingPed)
            local dist = #(pos - pedPos)

            if dist > 100 then
                if config.useTarget then
                    exports.ox_target:removeEntity(NetworkGetNetworkIdFromEntity(stealingPed), 'stealingped')
                end
                stealingPed = nil
                break
            end

            if not config.useTarget and IsEntityDead(stealingPed) and dist < 1.5 then
                if not textDrawn then
                    lib.showTextUI(locale('info.pick_up_button'))
                    textDrawn = true
                end

                if IsControlJustReleased(0, 38) then
                    lib.hideTextUI()
                    textDrawn = false

                    if lib.progressCircle({
                        duration = 2000,
                        position = 'bottom',
                        useWhileDead = false,
                        canCancel = true,
                        disable = { car = true, move = true },
                        anim = { dict = 'pickup_object', clip = 'pickup_low' }
                    }) then
                        TriggerServerEvent('qbx_drugs:server:giveStealItems')
                        TriggerEvent('inventory:client:ItemBox', exports.ox_inventory:Items()[stealData.item], 'add')
                        stealingPed = nil
                        stealData = {}
                    end
                end
            elseif not config.useTarget and textDrawn then
                 lib.hideTextUI()
                 textDrawn = false
            end

            Wait(250)
        end
        if textDrawn then lib.hideTextUI() textDrawn = false end
    end)
end

local function interactWithPed(ped)
    hasTarget = true
    local pedNetId = NetworkGetNetworkIdFromEntity(ped)
    local optionNames = { 'selldrugs', 'declineoffer' }

    -- Walking logic
    SetEntityAsNoLongerNeeded(ped)
    ClearPedTasks(ped)

    TaskGoToEntity(ped, cache.ped, -1, 1.5, 1.2, 1073741824, 0)

    local timeout = 200 -- Approx 10 seconds
    local arrived = false

    while timeout > 0 do
        local dist = #(GetEntityCoords(ped) - GetEntityCoords(cache.ped))
        if dist <= 1.6 then
            arrived = true
            break
        end
        if IsPedDeadOrDying(ped, true) or not isSelling then
            hasTarget = false
            return
        end
        timeout -= 1
        Wait(50)
    end

    if not arrived then
        hasTarget = false
        return
    end

    TaskLookAtEntity(ped, cache.ped, -1, 2048, 3)
    TaskTurnPedToFaceEntity(ped, cache.ped, -1)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT', 0, false)

    -- Robbery chance
    if currentOffer.shouldRob then
        TriggerServerEvent('qbx_drugs:server:robCornerDrugs')
        exports.qbx_core:Notify(locale('info.has_been_robbed', currentOffer.amount, currentOffer.chosen.label))

        stealingPed = ped
        stealData = {
            item = currentOffer.chosen.item,
            amount = currentOffer.amount
        }

        hasTarget = false
        ClearPedTasksImmediately(ped)
        TaskSmartFleePed(ped, cache.ped, 100.0, -1, false, false)
        addToLastPed(ped)
        handleRobbery(ped)
        return
    end

    -- Interaction logic
    if config.useTarget then
         exports.ox_target:addEntity(pedNetId, {
            {
                name = 'selldrugs',
                icon = 'fas fa-hand-holding-dollar',
                label = locale('info.target_drug_offer', currentOffer.amount, currentOffer.chosen.label, currentOffer.total),
                onSelect = function()
                    if lib.progressCircle({
                        duration = 2000,
                        position = 'bottom',
                        useWhileDead = false,
                        canCancel = false,
                        disable = { car = true, move = true },
                        anim = { dict = 'gestures@f@standing@casual', clip = 'gesture_point' }
                    }) then
                        TriggerServerEvent('qbx_drugs:server:sellCornerDrugs')
                        exports.ox_target:removeEntity(pedNetId, optionNames)

                        hasTarget = false
                        addToLastPed(ped)

                        SetPedKeepTask(ped, false)
                        SetEntityAsNoLongerNeeded(ped)
                        ClearPedTasks(ped)
                        TaskWanderStandard(ped, 10.0, 10)
                    end
                end
            },
            {
                name = 'declineoffer',
                icon = 'fas fa-x',
                label = locale('info.decline_offer'),
                onSelect = function()
                    exports.qbx_core:Notify(locale('error.offer_declined'), 'error')
                    exports.ox_target:removeEntity(pedNetId, optionNames)

                    hasTarget = false
                    addToLastPed(ped)

                    SetPedKeepTask(ped, false)
                    SetEntityAsNoLongerNeeded(ped)
                    ClearPedTasks(ped)
                    TaskWanderStandard(ped, 10.0, 10)
                end
            }
        })

        -- Cleanup if player walks away
        while hasTarget do
            local pPos = GetEntityCoords(cache.ped)
            local tPos = GetEntityCoords(ped)
            if #(pPos - tPos) > 3.0 or not isSelling then
                exports.ox_target:removeEntity(pedNetId, optionNames)
                hasTarget = false
                break
            end
            Wait(500)
        end
    else
        -- Text UI fallback
        while hasTarget do
            local pPos = GetEntityCoords(cache.ped)
            local tPos = GetEntityCoords(ped)

            if #(pPos - tPos) > 3.0 or not isSelling then
                lib.hideTextUI()
                hasTarget = false
                break
            end

            if not textDrawn then
                lib.showTextUI(locale('info.drug_offer', currentOffer.amount, currentOffer.chosen.label, currentOffer.total))
                textDrawn = true
            end

            if IsControlJustPressed(0, 38) then -- E
                lib.hideTextUI()
                textDrawn = false

                if lib.progressCircle({
                    duration = 2000,
                    position = 'bottom',
                    useWhileDead = false,
                    canCancel = false,
                    disable = { car = true, move = true },
                    anim = { dict = 'gestures@f@standing@casual', clip = 'gesture_point' }
                }) then
                    TriggerServerEvent('qbx_drugs:server:sellCornerDrugs')
                    hasTarget = false
                    addToLastPed(ped)
                    TaskWanderStandard(ped, 10.0, 10)
                end
            elseif IsControlJustPressed(0, 47) then -- G
                lib.hideTextUI()
                textDrawn = false
                exports.qbx_core:Notify(locale('error.offer_declined'), 'error')
                hasTarget = false
                addToLastPed(ped)
                TaskWanderStandard(ped, 10.0, 10)
            end

            Wait(0)
        end
    end
end

local function toggleSelling()
    if sellingPoint then
        stopSelling()
        exports.qbx_core:Notify(locale('info.stopped_selling_drugs'))
        return
    end

    local result = lib.callback.await('qbx_drugs:server:getDrugOffer', false)
    if not result then
        exports.qbx_core:Notify(locale('error.has_no_drugs'), 'error')
        return
    end

    -- Start Selling Loop
    isSelling = true
    currentOffer = nil -- Reset offer until we find a ped
    exports.qbx_core:Notify(locale('info.started_selling_drugs'))

    local startLocation = GetEntityCoords(cache.ped)

    sellingPoint = lib.points.new({
        coords = startLocation,
        distance = 15.0,
        interval = 1000,
        nearby = function()
            if not hasTarget and not currentOffer then
                local ped = lib.getClosestPed(startLocation, 10.0)
                if ped and not IsPedInAnyVehicle(ped, true) and not IsPedAPlayer(ped) then
                    local isUsed = false
                    for _, v in ipairs(lastPeds) do
                        if v == ped then isUsed = true break end
                    end

                    if not isUsed then
                         -- Get new offer for this specific interaction
                        local offer = lib.callback.await('qbx_drugs:server:getDrugOffer', false)
                        if offer then
                            currentOffer = offer
                            -- Run interaction in separate thread to avoid blocking point interval
                            CreateThread(function()
                                interactWithPed(ped)
                                currentOffer = nil -- Reset after interaction
                                Wait(math.random(3000, 5000)) -- Cooling period
                            end)
                        else
                            stopSelling()
                            exports.qbx_core:Notify(locale('error.no_drugs_left'), 'error')
                        end
                    end
                end
            end
        end,
        onExit = function()
            stopSelling()
            exports.qbx_core:Notify(locale('error.too_far_away'), 'error')
        end
    })
end

RegisterNetEvent('qbx_drugs:client:cornerselling', function()
    local currentCops = lib.callback.await('qbx_drugs:server:getPoliceCount', false)
    if currentCops >= config.minimumDrugSalePolice then
        toggleSelling()
    else
        exports.qbx_core:Notify(locale('error.not_enough_police', config.minimumDrugSalePolice), 'error')
    end
end)

RegisterCommand('sellcorner', function()
    TriggerEvent('qbx_drugs:client:cornerselling')
end, false)

AddStateBagChangeHandler('isLoggedIn', nil, function(_, _, value)
    if not value then
        stopSelling()
    end
end)