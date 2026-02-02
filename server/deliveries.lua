local config = require 'config.server'
local sharedConfig = require 'config.shared'

-- Server-side delivery tracking to prevent exploitation
local activeDeliveries = {}

exports('GetDealers', function()
    return sharedConfig.dealers
end)

RegisterNetEvent('qbx_drugs:server:randomPoliceAlert', function()
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end
    if config.policeCallChance >= math.random(1, 100) then
        TriggerEvent('police:server:policeAlert', locale('info.possible_drug_dealing'), nil, player.PlayerData.source)
    end
end)

RegisterNetEvent('qbx_drugs:server:giveDeliveryItems', function(deliveryData)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local item = sharedConfig.deliveryItems[deliveryData.item].item
    if not item then return end

    exports.ox_inventory:AddItem(src, item, deliveryData.amount)
end)

RegisterNetEvent('qbx_drugs:server:successDelivery', function(deliveryData, inTime)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)

    if not player then return end

    local item = sharedConfig.deliveryItems[deliveryData.item].item
    local itemAmount = deliveryData.amount
    local payout = deliveryData.itemData.payout * itemAmount
    local copsOnline = exports.qbx_core:GetDutyCountType('leo')
    local curRep = player.PlayerData.metadata.dealerrep
    local invItemCount = exports.ox_inventory:Search(src, 'count', item)
    if inTime then
        if invItemCount and invItemCount >= itemAmount then -- on time correct amount
            exports.ox_inventory:RemoveItem(src, item, itemAmount)
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
                TriggerClientEvent('qbx_drugs:client:sendDeliveryMail', src, 'perfect', deliveryData)
                player.Functions.SetMetaData('dealerrep', (curRep + config.deliveryRepGain))
            end)
        else
            exports.qbx_core:Notify(src, locale('error.order_not_right'), 'error')
            if invItemCount then
                local newItemAmount = invItemCount
                local modifiedPayout = deliveryData.itemData.payout * newItemAmount
                exports.ox_inventory:RemoveItem(src, item, newItemAmount)
                player.Functions.AddMoney('cash', math.floor(modifiedPayout / config.wrongAmountFee))
            end
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qbx_drugs:client:sendDeliveryMail', src, 'bad', deliveryData)
                player.Functions.SetMetaData('dealerrep', math.max(0, curRep - config.deliveryRepLoss))
            end)
        end
    else
        if invItemCount and invItemCount >= itemAmount then
            exports.qbx_core:Notify(src, locale('error.too_late'), 'error')
            exports.ox_inventory:RemoveItem(src, item, itemAmount)
            player.Functions.AddMoney('cash', math.floor(payout / config.overdueDeliveryFee), 'delivery-drugs-too-late')
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qbx_drugs:client:sendDeliveryMail', src, 'late', deliveryData)
                player.Functions.SetMetaData('dealerrep', math.max(0, curRep - config.deliveryRepLoss))
            end)
        else
            if invItemCount then
                local newItemAmount = invItemCount
                local modifiedPayout = deliveryData.itemData.payout * newItemAmount
                exports.qbx_core:Notify(src, locale('error.too_late'), 'error')
                exports.ox_inventory:RemoveItem(src, item, newItemAmount)
                player.Functions.AddMoney('cash', math.floor(modifiedPayout / config.overdueDeliveryFee), 'delivery-drugs-too-late')
                SetTimeout(math.random(5000, 10000), function()
                    TriggerClientEvent('qbx_drugs:client:sendDeliveryMail', src, 'late', deliveryData)
                    player.Functions.SetMetaData('dealerrep', math.max(0, curRep - config.deliveryRepLoss))
                end)
            end
        end
    end
end)


lib.addCommand('dealers', {
    help = 'To see the list of dealers',
    restricted = 'group.admin'
}, function(source)
    local dealersText = ''
    if sharedConfig.dealers ~= nil and next(sharedConfig.dealers) ~= nil then
        for _, v in pairs(sharedConfig.dealers) do
            dealersText = dealersText .. locale('info.list_dealers_name_prefix') .. v.name .. '<br>'
        end
        TriggerClientEvent('chat:addMessage', source, {
            color = { 0, 0, 255 },
            template = "<div class='chat-message advert'><div class='chat-message-body'><strong>' .. locale('info.list_dealers_title') .. '</strong><br><br> ' .. dealersText .. '</div></div>",
            args = {}
        })
    else
        exports.qbx_core:Notify(source, locale('error.no_dealers'), 'error')
    end
end)

lib.addCommand('dealergoto', {
    help = 'To teleport to dealer',
    params = {
        {
            name = 'name',
            type = 'string',
            help = locale('info.dealergoto_command_help1_help'),
            optional = false
        },
    },
    restricted = 'group.admin'
}, function(source, args)
    local dealerName = args.name
    if sharedConfig.dealers[dealerName] then
        local ped = GetPlayerPed(source)
        SetEntityCoords(ped, sharedConfig.dealers[dealerName].coords.x, sharedConfig.dealers[dealerName].coords.y, sharedConfig.dealers[dealerName].coords.z, false, false, false, false)
        exports.qbx_core:Notify(source, locale('success.teleported_to_dealer', dealerName), 'success')
    else
        exports.qbx_core:Notify(source, locale('error.dealer_not_exists'), 'error')
    end
end)
