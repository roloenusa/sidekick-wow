# Sidekick Addon - WoW Compatibility

## Version Information
- Addon Version: 3.0.0
- WoW Interface: 120100, 120007 (Midnight, Patch 12.0.7 live and 12.1.0)
- Tested On: WoW 12.0.x (Midnight)

## Status

Sidekick 3.0.0 is a rewrite for Midnight (Patch 12.0). The previous version
(2.0.0, interface 120001) does not work on current retail: it crashes on combat
entry and cannot compute target health. See the "What broke" section below.

## What broke in Midnight (Patch 12.0)

Patch 12.0 introduced two changes that the old code could not survive.

### 1. COMBAT_LOG_EVENT_UNFILTERED now errors on registration

Registering this event throws a Lua error. The old addon registered it on combat
entry, so the entire combat path failed. Death detection has been moved to the
new `UNIT_DIED` frame event, which carries the GUID of the unit that died.

### 2. Unit health is now a "Secret Value" in combat

In restricted combat the game returns opaque values for a unit's health.
Arithmetic and comparison on these values are immediate Lua errors, so the old
`(health / maxHealth) * 100` followed by `<= 10` no longer works. Blizzard still
allows addons to *display* state driven by secret values, just not to *read*
them.

## How Sidekick 3.0.0 handles it

### Low-health glow (secret-safe)

The glow no longer reads target health. It builds a curve with
`C_CurveUtil.CreateCurve()` that outputs full alpha at or below the low-health
threshold and 0 above it, then feeds the target's health percent through the
curve via `UnitHealthPercent("target", false, curve)`. The returned alpha is
piped straight into the glow frame with `SetAlpha`. The glow reflects the fight
without the addon ever knowing the health value. This mirrors the pattern used
by the Cell addon's Midnight migration.

### Target and death detection

- Combat entry/exit, spec, and target existence are still readable and used to
  gate the glow.
- `UnitCanAttack` and `UnitIsDead` are checked only when they are not secret
  (guarded with `issecretvalue`); in restricted content where they are secret,
  the glow relies on the health curve alone.
- Death detection uses `UNIT_DIED`, comparing the event GUID to the target GUID,
  guarded with `issecretvalue` so it never compares secret GUIDs.

### Resource bar

Player secondary resources (Astral Power, Combo Points, Holy Power, Chi, Runes,
Soul Shards, Arcane Charges, Essence) are not secret, so threshold markers and
colors work normally for them. Primary power (mana, energy, rage, fury) can be
secret in restricted combat; the current-power read is guarded with
`issecretvalue`, and value-based coloring is skipped rather than erroring when
the value is secret. Recoloring the Blizzard power bar is a display operation and
remains allowed; the addon never feeds a secret value into `SetStatusBarColor`.

## Known limitation to verify in-game

The curve range for `UnitHealthPercent` is assumed to be a 0-1 fraction (matching
Cell's real Midnight code). If the glow triggers at the wrong health level,
change `HEALTH_SHOW_THRESHOLD` and `HEALTH_HIDE_THRESHOLD` in `Sidekick.lua` from
`0.10` / `0.12` to `10` / `12`.

## References

- Secret Values: https://warcraft.wiki.gg/wiki/Secret_Values
- Patch 12.0.0 API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes
- Cell Midnight migration: https://github.com/enderneko/Cell/pull/457
