# qbx_drugs

A secure and advanced drug selling system for Qbox servers. This resource allows players to sell drugs to NPCs on street corners and undertake delivery missions for local dealers.

## Features

- **Corner Selling**: Players can sell drugs anywhere by interacting with locals.
    - Includes a robbery chance where locals might try to steal the drugs!
    - Requires police presence to be active.
- **Delivery Missions**: Players can work for dealers like Fred or Giovanni.
    - Request a delivery via email.
    - Pick up the package from the dealer's house.
    - Deliver it to a random location before time runs out.
    - Earn reputation to unlock better jobs and payouts.
- **Secure & Fair**: Built with advanced security to prevent cheaters from exploiting money or items. The server controls everything.
- **Optimized**: Designed to run smoothly without causing lag, even with many players online.
- **Phone Optional**: Works with or without `qb-phone`. If disabled, it uses notifications and automatic GPS navigation.

## Installation

1.  Download the resource and put it in your `resources` folder.
2.  Add `ensure qbx_drugs` to your `server.cfg`.
3.  Ensure you have the dependencies installed:
    - `qbx_core`
    - `ox_lib`
    - `ox_inventory`
    - `ox_target` (Optional, but recommended)

## Configuration Support

Everything you need to change is in the `config/` folder.

- **`config/shared.lua`**: Change the dealers, what drugs they accept, where deliveries go, and how much they pay.
    - *Note for Owners:* You can add as many delivery locations as you want here.
- **`config/client.lua`**:
    - `usePhone`: Set to `true` to use `qb-phone` email. Set to `false` for notifications and auto-GPS.
    - Other settings: Police count, success chances, etc.

### Enabling "Third Eye" (Target)
If you want to use `ox_target` (Alt-eye interaction) instead of button prompts:
1.  Open your `server.cfg`.
2.  Add this line: `setr UseTarget true`

## Commands

- `/sellcorner`: Toggles the "Sell Drugs" mode on/off.
- `/dealers`: (Admin) See a list of all active dealers and their locations.
- `/dealergoto [id]`: (Admin) Teleport directly to a dealer's location.
