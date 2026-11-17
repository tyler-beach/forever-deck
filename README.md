# Forever Deck

Compact **Blizzard-native** Steam Deck HUD for **World of Warcraft: Forever** (Interface `16001`), with planned RestedXP Forever path lines and Tauren Shaman PvE helpers.

Day-one focus is the HUD. Path overlay and shaman modules are stubs.

## Requirements

- WoW Forever client (Camelot) — mainline-style API, not Classic Era
- Steam Deck OLED (or desktop) with Blizzard built-in gamepad beta recommended
- Optional: [RestedXP Forever](https://shop.restedxp.com/forever/) for path overlay (Phase 2)

## Install (Steam Deck / Forever)

1. Copy the `ForeverDeck/` folder into your Forever AddOns directory:

   ```text
   <WoW Forever>/_forever_/Interface/AddOns/ForeverDeck/
   ```

   On Steam Deck this is typically under the Forever install prefix Steam uses for the game, ending in `_forever_/Interface/AddOns/`.

2. The folder must contain `ForeverDeck.toc` / `ForeverDeck_Forever.toc` and the Lua files (not a nested extra directory).

3. Restart Forever or `/reload`, then enable **ForeverDeck** in the AddOns list.

4. Slash commands:

   - `/foreverdeck status` — version, interface, module flags
   - `/foreverdeck hud` — toggle HUD scaffold
   - `/foreverdeck path` — toggle path stub
   - `/foreverdeck shaman` — toggle shaman stub

## Layout

```text
ForeverDeck/
  ForeverDeck.toc
  ForeverDeck_Forever.toc
  Core.lua
  Modules/HUD.lua
  Modules/RestedXPPath.lua
  Modules/ShamanPvE.lua
```

## Notes

- Forever detection: interface version in `[16000, 17000)`.
- RestedXP path feature will use public hooks/API only — this repo does not include RestedXP code.
- UI philosophy: overlays on default Blizzard UI, not a full replacement.
