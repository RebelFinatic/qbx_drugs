local sharedConfig = require 'config.shared'

-- Register dealer shops dynamically from config
for dealerName, dealerData in pairs(sharedConfig.dealers) do
    exports.ox_inventory:RegisterShop('Dealer_' .. dealerName, {
        name = dealerData.name,
        inventory = dealerData.products
    })
end
