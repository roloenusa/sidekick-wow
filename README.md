# Sidekick

A World of Warcraft addon for DPS players. It flags when you have no valid enemy
targeted and shows a screen-edge glow when your target is near death. It also
adds configurable thresholds, colors, and highlights to your resource bar.

- Version: 3.0.0
- Game version: WoW 12.0.x (Midnight), interface `120100, 120007`

## Features

- Low-health glow: an orange edge glow appears when the current target drops to
  the low-health threshold.
- Target reminder: warns you to target an enemy when you are in combat without a
  valid enemy selected.
- Resource bar customization: threshold markers, dynamic bar color, and
  highlights driven by your current resource value.

## Installation

1. Copy the `sidekick-wow` folder into
   `World of Warcraft/_retail_/Interface/AddOns/`.
2. Rename the folder to `Sidekick` if needed (the folder name should match the
   `.toc` file name).
3. Restart the game or run `/reload`.
4. Enable Sidekick in the AddOns list on the character select screen.

## Commands

Use `/sidekick` or the short form `/sk`.

| Command | Action |
|---------|--------|
| `/sk toggle` | Enable or disable target alerts |
| `/sk rb on` / `/sk rb off` | Enable or disable resource bar customization |
| `/sk rb add <value> <color> [name]` | Add a threshold |
| `/sk rb remove <index>` | Remove a threshold |
| `/sk rb clear` | Clear all thresholds |
| `/sk rb list` | List configured thresholds |
| `/sk rb markers` | Toggle threshold markers |
| `/sk rb colors` | Toggle dynamic bar colors |
| `/sk rb highlights` | Toggle threshold highlights |
| `/sk rb status` | Show current configuration |

Color formats accepted: `#FFFF00`, `1.0,1.0,0.0`, or `255,255,0`.

Example: `/sk rb add 40 #FFFF00 Starsurge`

## Midnight (Patch 12.0) notes

Patch 12.0 introduced "Secret Values", which prevent addons from reading or doing
math on a unit's health during combat. Sidekick 3.0.0 was rewritten to display
the low-health glow without ever reading the health value, using Blizzard's curve
system. It does not work on the pre-12.0 client. For the full breakdown of what
changed and why, see COMPATIBILITY.md and API_VERIFICATION.md.

## Files

| File | Purpose |
|------|---------|
| `Sidekick.toc` | Addon manifest and load order |
| `Sidekick.xml` | Loads the Lua files |
| `Sidekick.lua` | Target alerts and low-health glow |
| `ResourceBar.lua` | Resource bar customization |
| `COMPATIBILITY.md` | Midnight compatibility details |
| `API_VERIFICATION.md` | API status and items to verify in-game |
