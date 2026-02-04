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

---@param ped number
local function addToLastPed(ped)
    lastPeds[#lastPeds + 1] = ped
end

local function resetState()
    isSelling = false
    hasTarget = false
    currentOffer = nil
    stealingPed = nil
    stealData = {}
    zoneMade = false
    textDrawn = false
    lastPeds = {}
end

local function tooFarAway()
    exports.qbx_core:Notify(locale('error.too_far_away'), 'error')
    isSelling = false
    hasTarget = false
    currentOffer = nil
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
    local function walkToPlayer()
        SetEntityAsNoLongerNeeded(ped)
        ClearPedTasks(ped)
        local playerCoords = GetEntityCoords(cache.ped)
        TaskGoStraightToCoord(ped, playerCoords.x, playerCoords.y, playerCoords.z, 1.2, -1, 0.0, 0.0)

        while true do
            local pedCoords = GetEntityCoords(ped)
            local dist = #(playerCoords - pedCoords)

            if dist <= 1.5 then return true end
            if dist > 15.0 or IsPedDeadOrDying(ped, true) or not isSelling then return false end

            -- Recalculate target if player moves
            playerCoords = GetEntityCoords(cache.ped)
            TaskGoStraightToCoord(ped, playerCoords.x, playerCoords.y, playerCoords.z, 1.2, -1, 0.0, 0.0)

            Wait(500)
        end
    end

    if not walkToPlayer() then
        hasTarget = false
        return
    end

    TaskLookAtEntity(ped, cache.ped, -1, 2048, 3)
    TaskTurnPedToFaceEntity(ped, cache.ped, -1)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT', 0, false)

    -- Robbery chance
    if math.random(1, 100) <= config.robberyChance then
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
                    TriggerServerEvent('qbx_drugs:server:sellCornerDrugs')

                    lib.playAnim(cache.ped, 'gestures@f@standing@casual', 'gesture_point', 3.0, 3.0, -1, 49, 0, false, false, false)
                    exports.ox_target:removeEntity(pedNetId, optionNames)

                    hasTarget = false
                    addToLastPed(ped)

                    SetPedKeepTask(ped, false)
                    SetEntityAsNoLongerNeeded(ped)
                    ClearPedTasks(ped)
                    TaskWanderStandard(ped, 10.0, 10)
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
                TriggerServerEvent('qbx_drugs:server:sellCornerDrugs')
                lib.playAnim(cache.ped, 'gestures@f@standing@casual', 'gesture_point', 3.0, 3.0, -1, 49, 0, false, false, false)
                hasTarget = false
                addToLastPed(ped)
                TaskWanderStandard(ped, 10.0, 10)
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
    if isSelling then
        resetState()
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

    CreateThread(function()
        while isSelling do
            local myCoords = GetEntityCoords(cache.ped)

            -- Radius check
            if #(startLocation - myCoords) > 15.0 then
                tooFarAway()
                break
            end

            -- Find customer if we don't have one
            if not hasTarget and not currentOffer then
                local ped = lib.getClosestPed(myCoords, 10.0)
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
                            interactWithPed(ped)
                            currentOffer = nil -- Reset after interaction
                            Wait(math.random(3000, 5000)) -- Cooling period
                        else
                            isSelling = false
                            exports.qbx_core:Notify(locale('error.no_drugs_left'), 'error')
                        end
                    end
                end
            end

            Wait(1000)
        end
    end)
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
        resetState()
    end
end)