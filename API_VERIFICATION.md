# WoW Midnight (Patch 12.0.x) API Verification for Sidekick

This document tracks the APIs Sidekick uses and their status under Midnight
(Patch 12.0). The previous verification (which claimed 100/100 compatibility with
"12.0.1 / The War Within") was wrong: The War Within is Patch 11.x, and the two
core mechanisms of the old addon are broken on retail 12.0. See COMPATIBILITY.md.

## Interface Version
- TOC Interface: `120100, 120007` (12.1.0 and current live 12.0.7)

## Removed / broken APIs the old addon relied on

| API / Event | Status in 12.0 | Replacement |
|-------------|----------------|-------------|
| `COMBAT_LOG_EVENT_UNFILTERED` | Errors on `RegisterEvent` | `UNIT_DIED` frame event |
| `CombatLogGetCurrentEventInfo()` | No longer usable for this path | `UNIT_DIED` payload (GUID) |
| `UnitHealth` / `UnitHealthMax` arithmetic in combat | Secret Value; arithmetic/compare errors | `UnitHealthPercent` + curve |

## Secret-safe APIs now used

| API | Purpose | Source |
|-----|---------|--------|
| `issecretvalue(value)` | Detect secret values before math/compare | warcraft.wiki.gg/wiki/API_issecretvalue |
| `C_CurveUtil.CreateCurve()` | Build percent-to-alpha curve | warcraft.wiki.gg/wiki/API_C_CurveUtil.CreateCurve |
| `curve:AddPoint(input, output)` | Define curve points | Cell PR #457 (real usage) |
| `UnitHealthPercent(unit, usePredicted, curve)` | Health percent through curve, returns alpha | warcraft.wiki.gg/wiki/API_UnitHealthPercent |
| `Frame:SetAlpha(value)` | Accepts secret alpha to drive glow | warcraft.wiki.gg/wiki/Secret_Values |
| `UNIT_DIED` | Death detection (payload: unit GUID) | warcraft.wiki.gg/wiki/UNIT_DIED |

## APIs confirmed still stable

- `CreateFrame`, `RegisterEvent`, `RegisterUnitEvent`, `SetScript`, `Show`, `Hide`
- `GetSpecialization`, `GetSpecializationInfo` (global forms still exist)
- `UnitExists`, `UnitGUID`, `UnitAffectingCombat`
- `UnitPower`, `UnitPowerMax`, `UnitPowerType` (secondary resources not secret;
  primary power guarded with `issecretvalue`)
- `SetGradient(orientation, ColorMixin, ColorMixin)` with `CreateColor` objects
- `GetScreenWidth`, `GetScreenHeight`, `GetTime`, `PlaySound`, `C_Timer.After`
- `StatusBar:SetStatusBarColor` / `GetStatusBarColor` (display only; never fed a
  secret value by this addon)

## Items to verify in-game (could not be confirmed without the client)

1. Whether `UnitHealthPercent` feeds the curve a 0-1 fraction (assumed) or a
   0-100 value. If the glow triggers at the wrong point, flip the two threshold
   constants in `Sidekick.lua`.
2. Whether `UnitExists` / `UnitCanAttack` / `UnitIsDead` return secret values in
   restricted content. The code guards `UnitCanAttack` and `UnitIsDead` with
   `issecretvalue`; if `UnitExists` also becomes secret, add the same guard.
3. Exact secret behavior of player primary power. The resource bar guards for it,
   but the exact restriction may vary by patch as Blizzard relaxes limits.

## Sources

- Secret Values: https://warcraft.wiki.gg/wiki/Secret_Values
- Patch 12.0.0 API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes
- Cell Midnight migration (real reference code): https://github.com/enderneko/Cell/pull/457
- Icy-Veins on Midnight addon limits: https://www.icy-veins.com/wow/news/blizzard-relaxing-more-addon-limitations-in-midnight/
