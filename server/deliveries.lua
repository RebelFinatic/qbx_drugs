local config = require 'config.server'
local sharedConfig = require 'config.shared'

-- Server-side delivery tracking to prevent exploitation
local activeDeliveries = {}

exports('GetDealers', function()
    return sharedConfig.dealers
end)



RegisterNetEvent('qbx_drugs:server:requestDelivery', function(currentDealer)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    if activeDeliveries[src] then
        exports.qbx_core:Notify(src, locale('error.pending_delivery'), 'error')
        return
    end

    -- Server-side generation of delivery parameters
    local myRep = player.PlayerData.metadata.dealerrep or 0
    local availableItems = {}

    for i = 1, #sharedConfig.deliveryItems do
        if sharedConfig.deliveryItems[i].minrep <= myRep then
            availableItems[#availableItems+1] = i -- Store index, not key
        end
    end

    if #availableItems == 0 then
        exports.qbx_core:Notify(src, locale('error.no_available_deliveries'), 'error')
        return
    end

    local itemIndex = availableItems[math.random(1, #availableItems)]
    local itemData = sharedConfig.deliveryItems[itemIndex]
    local locationIndex = math.random(1, #sharedConfig.deliveryLocations)
    local locationData = sharedConfig.deliveryLocations[locationIndex]
    local amount = math.random(1, 3)

    local deliveryData = {
        id = os.time() + math.random(1000, 9999), -- Simple unique ID
        coords = locationData.coords,
        locationLabel = locationData.label,
        amount = amount,
        dealer = currentDealer,
        itemIndex = itemIndex, -- Store index to lookup config verify
        item = itemData.item,
        payout = itemData.payout,
        expiresAt = os.time() + 300 -- 5 minutes server side timeout
    }

    activeDeliveries[src] = deliveryData

    exports.ox_inventory:AddItem(src, itemData.item, amount)

    TriggerClientEvent('qbx_drugs:client:startDelivery', src, {
        coords = locationData.coords,
        locationLabel = locationData.label,
        amount = amount,
        itemLabel = exports.ox_inventory:Items()[itemData.item].label,
        dealer = currentDealer,
        item = itemData.item
    })
end)

RegisterNetEvent('qbx_drugs:server:successDelivery', function(inTime)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local delivery = activeDeliveries[src]
    if not delivery then
        exports.qbx_core:Notify(src, "No active delivery found", "error")
        return
    end

    local item = delivery.item
    local itemAmount = delivery.amount

    -- Validate item data from config again strictly
    local itemData = sharedConfig.deliveryItems[delivery.itemIndex]
    if not itemData or itemData.item ~= item then
        print('Possible exploit attempt by ID: '..src)
        activeDeliveries[src] = nil
        return
    end

    local payout = itemData.payout * itemAmount
    local copsOnline = exports.qbx_core:GetDutyCountType('leo')
    local curRep = player.PlayerData.metadata.dealerrep or 0
    local invItemCount = exports.ox_inventory:Search(src, 'count', item)

    if inTime then
        if invItemCount and invItemCount >= itemAmount then -- on time correct amount
            exports.ox_inventory:RemoveItem(src, item, itemAmount)

            -- Police Alert Chance
            if config.policeCallChance >= math.random(1, 100) then
                TriggerEvent('police:server:policeAlert', locale('info.possible_drug_dealing'), nil, src)
            end

            if copsOnline > 0 then
                local copModifier = copsOnline * config.policeDeliveryModifier
                if config.useMarkedBills then
                    local worth = math.floor(payout * copModifier)
                    local metadata = { worth = worth, description = 'Value: ' .. worth }
                    exports.ox_inventory:AddItem(src, 'markedbills', 1, metadata)
                else
                    player.Functions.AddMoney('cash', math.floor(payout * copModifier), 'drug-delivery')
                end
            else
                if config.useMarkedBills then
                    local metadata = { worth = payout, description = 'Value: ' .. payout }
                    exports.ox_inventory:AddItem(src, 'markedbills', 1, metadata)
                else
                    player.Functions.AddMoney('cash', payout, 'drug-delivery')
                end
            end
            exports.qbx_core:Notify(src, locale('success.order_delivered'), 'success')

            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qbx_drugs:client:sendDeliveryMail', src, 'perfect', { dealer = delivery.dealer })
                player.Functions.SetMetaData('dealerrep', (curRep + config.deliveryRepGain))
            end)
        else
            exports.qbx_core:Notify(src, locale('error.order_not_right'), 'error')
            if invItemCount and invItemCount > 0 then
                -- Partial delivery logic if needed, or just fail
                -- Original script removed all items they had and paid minimal?
                -- adhering roughly to original logic but safer
                local removeAmount = math.min(invItemCount, itemAmount)
                exports.ox_inventory:RemoveItem(src, item, removeAmount)
                -- Penalty pay? Or just nothing. Original: math.floor(modifiedPayout / config.wrongAmountFee)
                local modifiedPayout = itemData.payout * removeAmount
                player.Functions.AddMoney('cash', math.floor(modifiedPayout / config.wrongAmountFee))
            end
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qbx_drugs:client:sendDeliveryMail', src, 'bad', { dealer = delivery.dealer })
                player.Functions.SetMetaData('dealerrep', math.max(0, curRep - config.deliveryRepLoss))
            end)
        end
    else
        -- Late delivery
        if invItemCount and invItemCount >= itemAmount then
            exports.qbx_core:Notify(src, locale('error.too_late'), 'error')
            exports.ox_inventory:RemoveItem(src, item, itemAmount)
            player.Functions.AddMoney('cash', math.floor(payout / config.overdueDeliveryFee), 'delivery-drugs-too-late')
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qbx_drugs:client:sendDeliveryMail', src, 'late', { dealer = delivery.dealer })
                player.Functions.SetMetaData('dealerrep', math.max(0, curRep - config.deliveryRepLoss))
            end)
        else
            -- Late and missing items
             if invItemCount and invItemCount > 0 then
                local removeAmount = math.min(invItemCount, itemAmount)
                local modifiedPayout = itemData.payout * removeAmount
                exports.qbx_core:Notify(src, locale('error.too_late'), 'error')
                exports.ox_inventory:RemoveItem(src, item, removeAmount)
                player.Functions.AddMoney('cash', math.floor(modifiedPayout / config.overdueDeliveryFee), 'delivery-drugs-too-late')
                SetTimeout(math.random(5000, 10000), function()
                    TriggerClientEvent('qbx_drugs:client:sendDeliveryMail', src, 'late', { dealer = delivery.dealer })
                    player.Functions.SetMetaData('dealerrep', math.max(0, curRep - config.deliveryRepLoss))
                end)
            end
        end
    end

    activeDeliveries[src] = nil
end)


lib.addCommand('dealers', {
    help = 'To see the list of dealers',
    restricted = 'group.admin'
}, function(source)
    local dealersText = ''
    if sharedConfig.dealers ~= nil and next(sharedConfig.dealers) ~= nil then
        TriggerClientEvent('qbx_drugs:client:showDealerMenu', source, sharedConfig.dealers)
    else
        exports.qbx_core:Notify(source, locale('error.no_dealers'), 'error')
    end
end)

RegisterNetEvent('qbx_drugs:server:teleportToDealer', function(dealerName)
    local src = source
    if not IsPlayerAceAllowed(src, 'command') then return end

    if sharedConfig.dealers[dealerName] then
        local ped = GetPlayerPed(src)
        SetEntityCoords(ped, sharedConfig.dealers[dealerName].coords.x, sharedConfig.dealers[dealerName].coords.y, sharedConfig.dealers[dealerName].coords.z, false, false, false, false)
        exports.qbx_core:Notify(src, locale('success.teleported_to_dealer', dealerName), 'success')
    else
        exports.qbx_core:Notify(src, locale('error.dealer_not_exists'), 'error')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    activeDeliveries[src] = nil
end)
