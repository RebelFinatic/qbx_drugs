local config = require 'config.client'

-- Initialize state values
if LocalPlayer.state.lastPed == nil then
    LocalPlayer.state.lastPed = {}
end
if LocalPlayer.state.stealData == nil then
    LocalPlayer.state.stealData = {}
end
if LocalPlayer.state.zoneMade == nil then
    LocalPlayer.state.zoneMade = false
end
if LocalPlayer.state.textDrawn == nil then
    LocalPlayer.state.textDrawn = false
end

local function tooFarAway()
    exports.qbx_core:Notify(locale('error.too_far_away'), 'error')
    LocalPlayer.state.isSelling = false
    LocalPlayer.state.hasTarget = false
    LocalPlayer.state.currentOfferDrug = nil
end

local function robberyPed()
    if config.useTarget then
        local targetStealingPed = NetworkGetNetworkIdFromEntity(LocalPlayer.state.stealingPed)
        local options = {
            {
                name = 'stealingped',
                icon = 'fas fa-magnifying-glass',
                label = locale('info.search_ped'),
                onSelect = function()
                    lib.playAnim(cache.ped, 'pickup_object', 'pickup_low', 8.0, -8.0, -1, 1, 0, false, false, false)
                    Wait(2000)
                    ClearPedTasks(cache.ped)
                    TriggerServerEvent('qbx_drugs:server:giveStealItems')
                    TriggerEvent('inventory:client:ItemBox',
                        exports.ox_inventory:Items()[LocalPlayer.state.stealData.item], 'add')
                    LocalPlayer.state.stealingPed = nil
                    LocalPlayer.state.stealData = {}
                    exports.ox_target:removeEntity(targetStealingPed, 'stealingped')
                end,
                canInteract = function()
                    if IsEntityDead(LocalPlayer.state.stealingPed) then
                        return true
                    end
                end
            }
        }
        exports.ox_target:addEntity(targetStealingPed, options)
        CreateThread(function()
            while LocalPlayer.state.stealingPed do
                local pos = GetEntityCoords(cache.ped)
                local pedpos = GetEntityCoords(LocalPlayer.state.stealingPed)
                local dist = #(pos - pedpos)
                if dist > 100 then
                    LocalPlayer.state.stealingPed = nil
                    LocalPlayer.state.stealData = {}
                    exports.ox_target:removeEntity(targetStealingPed, 'stealingped')
                    break
                end
                Wait(100)
            end
        end)
    else
        local textDrawn = false
        CreateThread(function()
            while LocalPlayer.state.stealingPed do
                if IsEntityDead(LocalPlayer.state.stealingPed) then
                    local pos = GetEntityCoords(cache.ped)
                    local pedpos = GetEntityCoords(LocalPlayer.state.stealingPed)
                    if not config.useTarget and #(pos - pedpos) < 1.5 then
                        if not textDrawn then
                            textDrawn = true
                            lib.showTextUI(locale('info.pick_up_button'))
                        end
                        if IsControlJustReleased(0, 38) then
                            lib.hideTextUI()
                            textDrawn = false
                            lib.playAnim(cache.ped, 'pickup_object', 'pickup_low', 8.0, -8.0, -1, 1, 0, false, false,
                                false)
                            Wait(2000)
                            ClearPedTasks(cache.ped)
                            TriggerServerEvent('qbx_drugs:server:giveStealItems')
                            TriggerEvent('inventory:client:ItemBox',
                                exports.ox_inventory:Items()[LocalPlayer.state.stealData.item], 'add')
                            LocalPlayer.state.stealingPed = nil
                            LocalPlayer.state.stealData = {}
                        end
                    end
                else
                    local pos = GetEntityCoords(cache.ped)
                    local pedpos = GetEntityCoords(LocalPlayer.state.stealingPed)
                    if #(pos - pedpos) > 100 then
                        LocalPlayer.state.stealingPed = nil
                        LocalPlayer.state.stealData = {}
                        break
                    end
                end
                Wait(0)
            end
        end)
    end
end

local function sellToPed(ped)
    LocalPlayer.state.hasTarget = true
    local targetPedSale = NetworkGetNetworkIdFromEntity(ped)
    local optionNamesTargetPed = { 'selldrugs', 'declineoffer' }
    local lastPed = LocalPlayer.state.lastPed

    for i = 1, #lastPed, 1 do
        if lastPed[i] == ped then
            LocalPlayer.state.hasTarget = false
            return
        end
    end

    local successChance = math.random(1, 100)
    local getRobbed = math.random(1, 100)
    if successChance > config.successChance then
        LocalPlayer.state.hasTarget = false
        return
    end

    local currentOfferDrug = lib.callback.await('qbx_drugs:server:getDrugOffer', false)
    LocalPlayer.state.currentOfferDrug = currentOfferDrug

    if currentOfferDrug == nil then
        exports.qbx_core:Notify(locale('error.no_drugs_left'), 'error')
        return
    end

    SetEntityAsNoLongerNeeded(ped)
    ClearPedTasks(ped)

    local coords = GetEntityCoords(cache.ped, true)
    local pedCoords = GetEntityCoords(ped)
    local pedDist = #(coords - pedCoords)
    TaskGoStraightToCoord(ped, coords.x, coords.y, coords.z, getRobbed <= config.robberyChance and 15.0 or 1.2, -1, 0.0,
        0.0)

    while pedDist > 1.5 do
        coords = GetEntityCoords(cache.ped, true)
        pedCoords = GetEntityCoords(ped)
        TaskGoStraightToCoord(ped, coords.x, coords.y, coords.z, getRobbed <= config.robberyChance and 15.0 or 1.2, -1,
            0.0, 0.0)
        pedDist = #(coords - pedCoords)
        Wait(100)
    end

    TaskLookAtEntity(ped, cache.ped, 5500.0, 2048, 3)
    TaskTurnPedToFaceEntity(ped, cache.ped, 5500)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT', 0, false)

    if LocalPlayer.state.hasTarget then
        while pedDist < 1.5 and not IsPedDeadOrDying(ped, false) do
            local coords2 = GetEntityCoords(cache.ped, true)
            local pedCoords2 = GetEntityCoords(ped)
            local pedDist2 = #(coords2 - pedCoords2)
            if getRobbed <= config.robberyChance then
                TriggerServerEvent('qbx_drugs:server:robCornerDrugs')
                exports.qbx_core:Notify(locale('info.has_been_robbed', currentOfferDrug.amount,
                    currentOfferDrug.chosen.label))
                LocalPlayer.state.stealingPed = ped
                LocalPlayer.state.stealData = {
                    item = currentOfferDrug.chosen.item,
                    drugType = currentOfferDrug.idx,
                    amount = currentOfferDrug.amount,
                }
                LocalPlayer.state.hasTarget = false
                local moveTo = GetEntityCoords(cache.ped)
                local moveToCoords = vec3(moveTo.x + math.random(100, 500), moveTo.y + math.random(100, 500), moveTo.z)
                ClearPedTasksImmediately(ped)
                TaskGoStraightToCoord(ped, moveToCoords.x, moveToCoords.y, moveToCoords.z, 15.0, -1, 0.0, 0.0)
                local lastPed = LocalPlayer.state.lastPed
                lastPed[#lastPed + 1] = ped
                LocalPlayer.state.lastPed = lastPed
                robberyPed()
                break
            else
                if pedDist2 < 1.5 and LocalPlayer.state.isSelling then
                    if config.useTarget and not LocalPlayer.state.zoneMade then
                        LocalPlayer.state.zoneMade = true
                        local options = {
                            {
                                name = 'selldrugs',
                                icon = 'fas fa-hand-holding-dollar',
                                label = locale('info.target_drug_offer', currentOfferDrug.amount,
                                    currentOfferDrug.chosen.label, currentOfferDrug.total),
                                onSelect = function()
                                    TriggerServerEvent('qbx_drugs:server:sellCornerDrugs')
                                    LocalPlayer.state.currentOfferDrug = nil
                                    LocalPlayer.state.hasTarget = false
                                    lib.playAnim(cache.ped, 'gestures@f@standing@casual', 'gesture_point', 3.0, 3.0, -1,
                                        49, 0, false, false, false)
                                    Wait(650)
                                    ClearPedTasks(cache.ped)
                                    SetPedKeepTask(ped, false)
                                    SetEntityAsNoLongerNeeded(ped)
                                    ClearPedTasksImmediately(ped)
                                    local lastPed = LocalPlayer.state.lastPed
                                    lastPed[#lastPed + 1] = ped
                                    LocalPlayer.state.lastPed = lastPed
                                    exports.ox_target:removeEntity(targetPedSale, optionNamesTargetPed)
                                end,
                            },
                            {
                                name = 'declineoffer',
                                icon = 'fas fa-x',
                                label = locale('info.decline_offer'),
                                onSelect = function()
                                    LocalPlayer.state.currentOfferDrug = nil
                                    exports.qbx_core:Notify(locale('error.offer_declined'), 'error')
                                    LocalPlayer.state.hasTarget = false
                                    SetPedKeepTask(ped, false)
                                    SetEntityAsNoLongerNeeded(ped)
                                    ClearPedTasksImmediately(ped)
                                    local lastPed = LocalPlayer.state.lastPed
                                    lastPed[#lastPed + 1] = ped
                                    LocalPlayer.state.lastPed = lastPed
                                    exports.ox_target:removeEntity(targetPedSale, optionNamesTargetPed)
                                end,
                            },
                        }
                        exports.ox_target:addEntity(targetPedSale, options)
                    elseif not config.useTarget then
                        if not LocalPlayer.state.textDrawn then
                            LocalPlayer.state.textDrawn = true
                            lib.showTextUI(locale('info.drug_offer', currentOfferDrug.amount,
                                currentOfferDrug.chosen.label, currentOfferDrug.total))
                        end
                        if IsControlJustPressed(0, 38) then
                            lib.hideTextUI()
                            LocalPlayer.state.textDrawn = false
                            TriggerServerEvent('qbx_drugs:server:sellCornerDrugs')
                            LocalPlayer.state.hasTarget = false
                            lib.playAnim(cache.ped, 'gestures@f@standing@casual', 'gesture_point', 3.0, 3.0, -1, 49, 0,
                                false, false, false)
                            Wait(650)
                            ClearPedTasks(cache.ped)
                            SetPedKeepTask(ped, false)
                            SetEntityAsNoLongerNeeded(ped)
                            ClearPedTasksImmediately(ped)
                            local lastPed = LocalPlayer.state.lastPed
                            lastPed[#lastPed + 1] = ped
                            LocalPlayer.state.lastPed = lastPed
                            break
                        end
                        if IsControlJustPressed(0, 47) then
                            lib.hideTextUI()
                            LocalPlayer.state.textDrawn = false
                            exports.qbx_core:Notify(locale('error.offer_declined'), 'error')
                            LocalPlayer.state.hasTarget = false
                            SetPedKeepTask(ped, false)
                            SetEntityAsNoLongerNeeded(ped)
                            ClearPedTasksImmediately(ped)
                            local lastPed = LocalPlayer.state.lastPed
                            lastPed[#lastPed + 1] = ped
                            LocalPlayer.state.lastPed = lastPed
                            break
                        end
                    end
                else
                    if config.useTarget then
                        LocalPlayer.state.zoneMade = false
                        exports.ox_target:removeEntity(targetPedSale, optionNamesTargetPed)
                    else
                        if LocalPlayer.state.textDrawn then
                            lib.hideTextUI()
                            LocalPlayer.state.textDrawn = false
                        end
                    end
                    LocalPlayer.state.hasTarget = false
                    SetPedKeepTask(ped, false)
                    SetEntityAsNoLongerNeeded(ped)
                    ClearPedTasksImmediately(ped)
                    local lastPed = LocalPlayer.state.lastPed
                    lastPed[#lastPed + 1] = ped
                    LocalPlayer.state.lastPed = lastPed
                    break
                end
            end
            Wait(0)
        end
        Wait(math.random(4000, 7000))
    end
end

local function toggleSelling()
    if not LocalPlayer.state.isSelling then
        LocalPlayer.state.isSelling = true
        exports.qbx_core:Notify(locale('info.started_selling_drugs'))
        local startLocation = GetEntityCoords(cache.ped)
        CreateThread(function()
            while LocalPlayer.state.isSelling do
                local coords = GetEntityCoords(cache.ped)
                if not LocalPlayer.state.hasTarget then
                    local closestPed = lib.getClosestPed(coords, 15.0)
                    if closestPed ~= nil and not IsPedInAnyVehicle(closestPed, false) and GetPedType(closestPed) ~= 28 then
                        sellToPed(closestPed)
                    end
                end
                local startDist = #(startLocation - coords)
                if startDist > 10 then
                    tooFarAway()
                end
                Wait(250)
            end
        end)
    else
        LocalPlayer.state.stealingPed = nil
        LocalPlayer.state.stealData = {}
        LocalPlayer.state.isSelling = false
        LocalPlayer.state.zoneMade = false
        LocalPlayer.state.textDrawn = false
        exports.qbx_core:Notify(locale('info.stopped_selling_drugs'))
    end
end

-- Events

RegisterNetEvent('qbx_drugs:client:cornerselling', function()
    local currentCops = lib.callback.await('qbx_drugs:server:getPoliceCount', false)
    if currentCops >= config.minimumDrugSalePolice then
        local hasDrugs = not not lib.callback.await('qbx_drugs:server:getDrugOffer', false)
        if hasDrugs then
            toggleSelling()
            exports.qbx_core:Notify(locale('success.corner_selling_enabled'), 'success')
        else
            exports.qbx_core:Notify(locale('error.has_no_drugs'), 'error')
        end
    else
        exports.qbx_core:Notify(locale('error.not_enough_police', config.minimumDrugSalePolice), 'error')
    end
end)

-- Command for corner selling
RegisterCommand('sellcorner', function()
    TriggerEvent('qbx_drugs:client:cornerselling')
end, false)

-- Cleanup on disconnect
AddStateBagChangeHandler('isLoggedIn', nil, function(_, _, value)
    if not value then
        LocalPlayer.state.isSelling = false
        LocalPlayer.state.hasTarget = false
        LocalPlayer.state.currentOfferDrug = nil
        LocalPlayer.state.lastPed = {}
        LocalPlayer.state.stealingPed = nil
        LocalPlayer.state.stealData = {}
        LocalPlayer.state.zoneMade = false
        LocalPlayer.state.textDrawn = false
    end
end)