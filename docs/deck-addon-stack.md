# Forever Deck — recommended addon stack

Short list for a **rich Steam Deck OLED** Forever experience that stays one look with
**Improved Forever Immersion** (gold / Morpheus / diamond chrome). Prefer soft-dep
skins or IF-native modules over vendoring more addons.

Install forever-deck first (WoWDeck Manual Install → `tyler-beach/forever-deck`, or the
[All-forever zip](https://github.com/tyler-beach/forever-deck/releases/latest/download/ImprovedForever-All-forever.zip)).
That zip already includes every `ImprovedForever*` module **and** vendored **Forever Totems**.

---

## 1. Must-have (full Deck feel)

| Addon | Role | Install | Align with IF |
|---|---|---|---|
| **forever-deck** (this pack) | Immersion HUD, Wheel, Quest Tracker, Map, Junk, … + Forever Totems | WoWDeck / All-forever zip | **Native** — this *is* the look |
| [**Spoken**](https://www.curseforge.com/wow/addons/spoken) | NPC / quest voice + textures Immersion uses | CurseForge (Forever flavor) | **Required** by Immersion (not a skin target) |
| [**Spoken Quests**](https://www.curseforge.com/wow/addons/spoken-quests) *(optional)* | Extra quest VO | CurseForge | Soft-dep of Immersion |
| [**RXPGuides**](https://www.curseforge.com/wow/addons/restedxp-guide) | Leveling / profession / dungeon / legacy routes | CurseForge + Forever packs / `/rxp import` | **Soft-dep done:** Quest Tracker blocks + Immersion nameplate highlights. **Next:** IF path lines on map (build, don’t skin TomTom) |

---

## 2. Dungeons & meters (rich, leave chrome)

| Addon | Role | Install | Align with IF |
|---|---|---|---|
| [**DBM-Core**](https://www.curseforge.com/wow/addons/deadly-boss-mods) | Boss / trash timers & warnings | CurseForge → **WoW Forever** flavor | **Leave stock** for now. Optional later: Immersion gold timer bars (hard) |
| [**DBM — Forever and Vanilla**](https://www.curseforge.com/wow/addons/dbm-vanilla) | Forever / Vanilla raid modules | CurseForge (requires Core) | Leave stock |
| [**Details!**](https://www.curseforge.com/wow/addons/details) *(optional)* | Damage / healing meter | CurseForge Forever flavor | **Leave stock** — not Deck-primary; don’t fight Immersion |

BigWigs is fine instead of DBM if you prefer it — same rule: functional, don’t reskin first.

---

## 3. Shaman (class depth)

| Addon | Role | Install | Align with IF |
|---|---|---|---|
| **Forever Totems** | Totem bar, Call sets, macros, imbue, swing | **In All pack** (vendored MIT) | **Done** — Immersion chrome baked in (+ Immersion → Totems skin toggle) |
| [**TotemWatch**](https://www.curseforge.com/wow/addons) *(optional)* | Dungeon totem recommendations | Only if you want boss-set tips beyond Forever Totems | Soft-dep skin **possible** later; don’t run two full totem bars |
| [**ShamanForever / InterHUD**](https://github.com/cassidymichael/ShamanForever) *(optional)* | Full shaman combat HUD | GitHub / Curse if published | **Leave stock** — heavy; conflicts with Immersion density. Prefer thin IF Shock/prep glance instead |

Default shaman stack: **forever-deck + Forever Totems**. Add TotemWatch *or* InterHUD only if you feel a gap — not both.

---

## 4. Skip (IF already covers or fights the look)

| Addon | Why skip |
|---|---|
| TomTom / RestedXP-TomTom | Arrow fight with RXP; no thick path lines — **build IF paths** instead |
| Plater / custom nameplates | Immersion plates + RXP target highlight |
| ElvUI / Bartender / Dominos | Immersion + Wheel own the Deck HUD / gamepad bar |
| Classic TotemTimers | RXP arrow conflict; Forever Totems replaces it |
| WeakAuras rotation packs | Out of scope; not Blizzard-native Deck chrome |

---

## 5. IF work still ahead (not more installs)

| Build | Why |
|---|---|
| **RXP path lines** (Map / QuestTracker soft-dep) | Thick OLED path player → current → next — unique gap |
| **Shaman glance** (optional) | Earth Shock interrupt flash + OOC imbue/shield prep as Immersion cards |
| **Shared chrome helpers** | One diamond/gold toolkit for future soft-dep skins (e.g. DBM bars) |
| **DBM bar tint** (optional, later) | Only if stock timers feel visually loud on Deck |

---

## One-line install order

1. forever-deck All-forever  
2. Spoken (+ Spoken Quests if you want VO)  
3. RXPGuides (+ Forever packs / imports)  
4. DBM-Core Forever + DBM Forever/Vanilla  
5. Optional: Details!, TotemWatch *or* InterHUD  

**Reskin rule:** skin when the addon is MIT/friendly and a thin chrome pass reads as Immersion (Totems). Otherwise install for function and leave look, or **build the cue inside IF**.
