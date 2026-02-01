local dealerProducts = {
    { name = 'weed_white-widow', price = 15 },
    { name = 'weed_skunk', price = 15 },
    { name = 'weed_purple-haze', price = 15 },
    { name = 'weed_og-kush', price = 15 },
    { name = 'weed_amnesia', price = 15 },
    { name = 'weed_white-widow_seed', price = 15 },
    { name = 'weed_skunk_seed', price = 15 },
    { name = 'weed_purple-haze_seed', price = 15 },
    { name = 'weed_og-kush_seed', price = 15 },
    { name = 'weed_amnesia_seed', price = 15 },
}

return {
    dealers = {
        ['Downtown_Dave'] = {
            name = 'Downtown_Dave',
            coords = vec3(137.5, -1705.2, 29.3),
            time = { min = 6, max = 20 },
            products = dealerProducts
        },
        ['Vinewood_Vic'] = {
            name = 'Vinewood_Vic',
            coords = vec3(-306.8, 6299.5, 32.4),
            time = { min = 4, max = 18 },
            products = dealerProducts
        },
        ['Sandy_Sam'] = {
            name = 'Sandy_Sam',
            coords = vec3(1962.3, 3740.8, 32.3),
            time = { min = 5, max = 21 },
            products = dealerProducts
        },
        ['Paleto_Pete'] = {
            name = 'Paleto_Pete',
            coords = vec3(-114.4, 6450.2, 31.5),
            time = { min = 3, max = 19 },
            products = dealerProducts
        },
        ['Mirror_Mike'] = {
            name = 'Mirror_Mike',
            coords = vec3(1234.5, -678.9, 66.4),
            time = { min = 2, max = 22 },
            products = dealerProducts
        },
    },
    deliveryItems = {
        {
            item = 'weed_brick',
            minrep = 0,
            payout = 1000
        },
        {
            item = 'coke_brick',
            minrep = 0,
            payout = 1000
        },
    },
}