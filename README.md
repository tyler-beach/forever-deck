# Forever Deck

Compact **Blizzard-native** Steam Deck HUD for **World of Warcraft: Forever** (Interface `16001`), with planned RestedXP Forever path lines and Tauren Shaman PvE helpers.

Phase 1 (this release): compact Deck HUD that **scales/repositions stock Blizzard frames**, keeps center FOV clear, and surfaces install/debug errors clearly on Deck.

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

4. Smoke-check:

   - Player/target frames should sit at the top corners (scaled ~0.85).
   - Center FOV stays clear; casting bar / buffs nudged off dead-center.
   - Bottom strip shows compact player/target HP + resource %.
   - `/foreverdeck status` and `/fd debug` print module + last-error state.

## Slash commands

| Command | Action |
|---------|--------|
| `/foreverdeck status` | Version, interface build, module load flags |
| `/foreverdeck debug` or `/fd debug` | Status plus last errors + optional frame probe |
| `/foreverdeck hud` | Toggle HUD layout (restores stock anchors when off) |
| `/foreverdeck path` | Toggle path stub (Phase 2) |
| `/foreverdeck shaman` | Toggle shaman stub (Phase 3) |
| `/fdeck` / `/fd` | Aliases for `/foreverdeck` |

## Diagnostics

Init failures are never silent:

- `ForeverDeck.Error:Raise/Assert` — fatal, `error()` with `ForeverDeck[Module]:Fn — message`
- Missing Forever interface range or required Blizzard frames → red chat + `UIErrorsFrame`
- Risky frame hooks run under `pcall`; failures print `ForeverDeck: HUD failed to attach X because Y`
- Soft-deps (e.g. RestedXP) warn **once** and do not crash the HUD

## SavedVariables (`ForeverDeckDB.profile`)

- `hudEnabled`, `hudScale`
- `hud.player` / `hud.target` / `hud.bagsMicro` / `hud.questGlance` — scale + anchors
- `hud.panels.*` — which panels to apply
- `hud.clearCenterFOV` — nudge cast bar / buffs off center

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
- UI philosophy: overlays / reposition on default Blizzard UI, not a full replacement.
