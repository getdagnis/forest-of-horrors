# Changelog

This file records changes made in the Studio/manual-source workflow. The live Studio place remains authoritative; an entry marked **source only** still needs to be manually copied to Studio and play-tested.

## Unreleased — 2026-08-13

### Added

- `CreepyMonsterSystem` (**source only**) centralizes creepyMonster behavior and disables each model's legacy `Follow` and `Damage Script` descendants.
  - `creepyMonster`: 320 HP, 5 points, 60 damage.
  - `creepyMonsterOrange`: 420 HP, 10 points, 120 damage.
  - `creepyMonsterWhite`: 520 HP, 15 points, 240 damage.
  - Creepy monsters prioritize players; lower-HP monster hunting is deliberately rare and rate-limited.
- `PlayerHealthSystem` was added as a Studio/manual-source script.
  - Sets player base maximum health to 120.
  - Implements a BigMac-based +10 maximum-health bonus, up to +60, with a 30-second respawn timer.
  - Now includes a healing sound, `+N health` floating label, a bright green double flash with a PointLight, and a brief green flash on the consumed burger.
- `MonsterHitFeedback` (**source only**) is a shared `ReplicatedStorage` ModuleScript for all weapon hit feedback.
  - Displays a tokenized `current / max` health label so an older hit cannot hide a newer label.
  - Uses a full-body material-Neon flash, restores original materials/colours after 0.25 seconds, and emits a short PointLight.
- `SwordScript.luau` was copied into the repository as a backup of the current Light Saber script. It is not yet mapped to a live Tool path in `default.project.json`.

### Changed

- LightSaber stability recovery (**source only**) now isolates its pickup lifecycle in `WeaponSpawnSystem`.
  - It manages every `LightSaberSpawnPoint` named BasePart (or `WeaponName = "LightSaber"`); the point's unique Studio name is its stable key, so copied attributes cannot collapse several points into one spawn.
  - A server-only ownership lease rejects a second enabled `WeaponSpawnSystem`; an untagged legacy Saber near a configured point blocks spawning with a warning instead of silently adding another copy.
  - World Sabers are anchored only while waiting to be picked up. All parts are unanchored before `RightGrip` is used, preventing the anchored Tool from freezing the character.
  - It disables a legacy `SaberSpawner` on a migrated Saber defensively. Remove that Script from the canonical template in Studio so the global controller remains the sole respawn owner.
- `SwordScript.luau` and `LightSaberSlashFlash.client.luau` restore the backup-13 Saber behavior: ignite sound, light-blue short monster flash, brief blade-tip light per slash, knockback, and all-blade/hilt contact detection. They deliberately do not use the newer shared weapon-feedback helper.
- `MonsterManager` now distinguishes three creepy variants:
  - black `creepyMonster`: 320 HP / 5 points;
  - orange `creepyMonsterOrange`: 420 HP / 10 points;
  - white `creepyMonsterWhite`: 520 HP / 15 points.
- `SafeZoneManager` now keeps an explicit outside-zone sentinel and can find a fallback BasePart for models without a normal HumanoidRootPart. This fixes the previous case where outside monsters were not monitored for entry into the McDonald's/Donut Store safe zones.
- `MonsterGunDamageSystem` is restored to 20 damage and uses the shared full-body pink Neon/PointLight hit feedback. Its pink muzzle and impact endpoints now emit real light as well.
- MonsterBlaster is restored to 150–450 charged damage; direct ground shockwaves are 20 studs / 150 damage. Its muzzle, beam endpoint, and ground shockwave now use blue PointLights and bright Neon energy.
- Monster bombs now beep on a one-second cadence during warning, spatialize warning sound to at most 115 studs, flash a bright pink PointLight per beep, and keep a three-pulse bright pink blast visible for four seconds. Damage remains once at the explosion moment and bomb monsters are excluded from blast damage.
- `WeaponInventoryGuard` now preserves Roblox's normal pickup path and destroys only a newly collected duplicate unique weapon. A player therefore keeps one ordinary weapon slot per name without prompts, tool movement, or pickup physics changes.
- `WeaponSpawnSystem` no longer deletes pre-existing world MonsterGuns on startup.
- `MonsterBlasterGunSpawner.luau` was added as the equivalent deferred collection handler for the standalone world Blaster pickup.
- `SwordScript.luau` now routes monster damage through `MonsterManager` and `MonsterHitFeedback`; it emits an actual PointLight at `Handle.Touched`, preserving contact-timed slash illumination rather than using a generic overlay.

### Camera, HUD, and targeting work

- `CameraController`, `WeaponCrosshairClient`, and `WeaponTargetContour` exist as manual-source additions. They must be placed as **LocalScripts** in their documented Studio locations; do not place client code under `ServerScriptService`.
- MonsterBlaster charge HUD source includes respawn/unequip cleanup because its ScreenGui uses `ResetOnSpawn = false`.

## Review — known regressions and required follow-up

These are observed issues, not completed features.

### P0 — combat feedback requires an isolated Studio test

- The recovery sources now restore full-body Neon flashes and physical PointLights, but none of this proves the active Studio Tools have been replaced. Test one MonsterGun, one MonsterBlaster, and one Light Saber after the exact manual replacements below.
- There must be only one active MonsterGun server damage owner. Keep `ServerScriptService.MonsterGunDamageSystem` enabled and disable the old `MonsterGunServer` Script inside every active MonsterGun Tool. Otherwise two handlers fight over the same `ShootEvent`, causing inconsistent damage, colour, and labels.

### P0 — health-label limitations

- The shared helper now falls back from `HumanoidRootPart`/`Head` to `PrimaryPart` or any BasePart and uses a hide token. The `0 / max` label still needs play-test verification on rapidly disintegrating corpses because their parts can be removed by legacy death code.

### P1 — PlayerHealthSystem scope remains limited

- BigMac feedback/removal now preserves each original part's transparency and collision/query/touch state. If it stays visible, the active Studio script or object path differs and should be audited before another change.
- The script still handles only direct `Workspace["McDonald's"].BigMac`. The soda machine is deliberately not guessed: inspect its exact object path/name and add it as a separate safe change.

### P1 — Blaster visual path needs Studio installation verification

- Beam and muzzle are client-side; the active Tool must contain the current `MonsterBlasterClientScript` LocalScript. The shockwave is server-side; the active Tool must contain the current `MonsterBlasterServer` Script. Source changes alone cannot change the live pickup.

### P1 — performance caution

- Do not layer more per-monster `while true` / `Touched` scripts onto the existing marketplace models. Use central systems and measure with Studio Script Performance before optimization.
- The old creepy `Follow` and `Damage Script` instances must remain disabled when `CreepyMonsterSystem` is active; otherwise they reintroduce broad Workspace scans and uncontrolled NPC-on-NPC damage.

## Next safe test order

1. Verify the active Studio paths/classes for MonsterGun, MonsterBlaster, and Light Saber scripts.
2. Restore one reliable material-Neon hit flash and tokenized HP label helper, then test it on every configured monster type.
3. Verify the exact BigMac and soda-machine object paths; add feedback/removal only after that audit.
4. Restore Blaster beam/muzzle/shockwave light in the active Tool client/server scripts.
5. Test Light Saber separately, preserving its slash-timed illumination behavior.
