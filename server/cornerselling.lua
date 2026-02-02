local config = require 'config.server'

-- Server-side offer tracking to prevent client manipulation
local activeOffers = {}

-- Callback to get the current count of on-duty police officers
lib.callback.register('qbx_drugs:server:getPoliceCount', function()
    local policeCount = exports.qbx_core:GetDutyCountJob('police')
    return policeCount or 0
end)

local function getAvailableDrugs(source)
    local availableDrugs = {}
    local player = exports.qbx_core:GetPlayer(source)

    if not player then return nil end

    for i = 1, #config.cornerSellingDrugsList do
        local itemName = config.cornerSellingDrugsList[i]
        local itemCount = exports.ox_inventory:Search(source, 'count', itemName)
        if itemCount > 0 then
            availableDrugs[#availableDrugs + 1] = {
                item = itemName,
                amount = itemCount,
                label = exports.ox_inventory:Items()[itemName].label
            }
        end
    end
    return table.type(availableDrugs) ~= 'empty' and availableDrugs or nil
end

lib.callback.register('qbx_drugs:server:getDrugOffer', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return nil end
    local availableDrugs = getAvailableDrugs(player.PlayerData.source)
    if availableDrugs == nil then return nil end

    local randomDrug = math.random(1, #availableDrugs)
    local chosenDrug = availableDrugs[randomDrug]
    local offeredAmount = math.random(1, chosenDrug.amount > 15 and 15 or chosenDrug.amount)
    local basePrice = math.random(config.cornerSellingDrugsPrice[chosenDrug.item].min,
        config.cornerSellingDrugsPrice[chosenDrug.item].max)
    local totalPrice = config.scamChance >= math.random(1, 100) and basePrice * offeredAmount or
        math.random(3, 10) * offeredAmount

    -- Store offer server-side for validation
    local offer = { chosen = chosenDrug, idx = randomDrug, amount = offeredAmount, total = totalPrice }
    activeOffers[source] = offer

    return offer
end)

-- Track robbery state for giveStealItems validation
local activeRobberies = {}

RegisterNetEvent('qbx_drugs:server:giveStealItems', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)

    if not player then return end

    -- Validate against stored robbery state
    local robbery = activeRobberies[src]
    if not robbery then return end

    local success, err = pcall(function()
        exports.ox_inventory:AddItem(src, robbery.item, robbery.amount)
    end)

    if not success then
        print('[qbx_drugs] Failed to add stolen items: ' .. tostring(err))
    end

    activeRobberies[src] = nil
end)

RegisterNetEvent('qbx_drugs:server:sellCornerDrugs', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)

    if not player then return end

    -- Validate against stored offer
    local offer = activeOffers[src]
    if not offer then return end

    local item = offer.chosen.item
    local amount = offer.amount
    local price = offer.total

    local hasItem = player.Functions.GetItemByName(item)
    if hasItem and hasItem.amount >= amount then
        local success, err = pcall(function()
            exports.ox_inventory:RemoveItem(src, item, amount)
        end)

        if success then
            exports.qbx_core:Notify(src, locale('success.offer_accepted'), 'success')
            player.Functions.AddMoney('cash', price, 'sold-cornerdrugs')
            if config.policeCallChance >= math.random(1, 100) then
                TriggerEvent('police:server:policeAlert', locale('info.possible_drug_dealing'), nil, src)
            end
        else
            print('[qbx_drugs] Failed to remove item: ' .. tostring(err))
        end
    else
        TriggerClientEvent('qbx_drugs:client:cornerselling', src)
    end

    activeOffers[src] = nil
end)

RegisterNetEvent('qbx_drugs:server:robCornerDrugs', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)

    if not player then return end

    -- Validate against stored offer
    local offer = activeOffers[src]
    if not offer then return end

    local item = offer.chosen.item
    local amount = offer.amount

    local success, err = pcall(function()
        exports.ox_inventory:RemoveItem(src, item, amount)
    end)

    if success then
        -- Store robbery state for later retrieval
        activeRobberies[src] = {
            item = item,
            amount = amount
        }
    else
        print('[qbx_drugs] Failed to remove robbed item: ' .. tostring(err))
    end

    activeOffers[src] = nil
end)

-- Cleanup on player disconnect
AddEventHandler('playerDropped', function()
    local src = source
    activeOffers[src] = nil
    activeRobberies[src] = nil
end)