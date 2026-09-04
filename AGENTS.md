# Forest of Horrors — agent guide

## Working agreement

- **`MONSTER_AI_ECOSYSTEM.md` is a MUST OBEY reference** for any monster, zombie, guardian, lure, safety-zone, respawn, death, round-count, or monster-event change. In particular, never force-reposition a living monster to satisfy a distribution or safety goal.
- The live Roblox Studio place is the current source of truth. **Rojo has been uninstalled** after a bad sync/conflict incident. Do not ask the user to reconnect it or assume filesystem changes reach Studio.
- The files in this repository are the manual code backup and drafting area. When changing one, state exactly which Studio instance must be replaced or added. The user copies code manually.
- Do not make broad cleanup/refactor passes in the live place. It is an old, marketplace-model-heavy game with many legacy scripts and asset warnings. Work one system at a time and test each slice before continuing.
- Preserve user visual/UI work in Studio. `GameFlowHud.client.luau` programmatically creates UI and can overwrite Studio UI edits; do not touch it unless the user explicitly requests that UI behavior.
- The known stable source checkpoint is commit `eba70ef`. Treat later uncommitted source as active work; preserve it and do not reset/revert it unless asked.
- Never declare a feature working merely because source builds. Test evidence from the user’s Studio/Roblox play session is authoritative.

## Project structure and Studio placement

`default.project.json` documents intended placements, but is **not a live sync contract**.

| Repository file | Intended Studio location | Notes |
| --- | --- | --- |
| `src/ReplicatedStorage/MonsterManager.luau` | `ReplicatedStorage.MonsterManager` ModuleScript | Canonical monster stats/scoring API. |
| `src/ServerScriptService/MonsterSystem.server.luau` | `ServerScriptService.MonsterSystem` Script | HP setup, score, respawn, monster count, round flow. |
| `src/ServerScriptService/ZombieAISystem.server.luau` | `ServerScriptService.ZombieAISystem` Script | Central Drooling Zombie registration. Only one enabled copy. |
| `src/ServerStorage/ROBLOX_ZombieAI.luau` | `ServerStorage.ROBLOX_ZombieAI` ModuleScript | Shared zombie AI. |
| `src/ServerScriptService/CreepyMonsterSystem.server.luau` | `ServerScriptService.CreepyMonsterSystem` Script | Central creepy AI; disables old `Follow` / `Damage Script` descendants itself. |
| `src/ServerScriptService/MonsterGunDamageSystem.server.luau` | `ServerScriptService.MonsterGunDamageSystem` Script | Binds active MonsterGun Tools dynamically. |
| `src/ServerStorage/MonsterBlasterServer.server.luau` | Active MonsterBlaster Tool’s `ServerScript` | It is **not** a ScriptService script. |
| `src/ReplicatedStorage/MonsterBlasterConfig.luau` | `ReplicatedStorage.MonsterBlasterConfig` ModuleScript | Shared charge, damage, cooldown, and shockwave tuning. |
| `src/ServerStorage/WeaponTemplates/ClientScript.luau` | MonsterGun Tool `ClientScript` LocalScript | Gun visual/client input. |
| `src/ServerStorage/WeaponTemplates/MonsterBlasterClientScript.luau` | MonsterBlaster Tool `ClientScript` LocalScript | Blaster charge/beam/HUD client behavior. |
| `src/ServerScriptService/MonsterBlasterSpawnSystem.server.luau` | `ServerScriptService.MonsterBlasterSpawnSystem` Script | Sole world-pickup owner; clones `ServerStorage.WeaponTemplates.MonsterBlaster`. |
| `src/ServerStorage/WeaponTemplates/WeaponCrosshairClient.luau` | Each gun Tool’s `WeaponCrosshairClient` **LocalScript** | Must be a child of each Tool, never a server Script. |
| `src/StarterPlayer/StarterPlayerScripts/CameraController.client.luau` | `StarterPlayer.StarterPlayerScripts.CameraController` LocalScript | Global Z/FPS and RMB shoulder aim. |
| `src/StarterPlayer/StarterPlayerScripts/WeaponTargetContour.client.luau` | `StarterPlayer.StarterPlayerScripts.WeaponTargetContour` LocalScript | Local pink/blue weapon target outline. |

## Monster model conventions

`MonsterManager` defines which models count as monsters. It also determines their real canonical Humanoid. Do not bypass it with direct model-name scans unless absolutely necessary.

Current intended configs:

| Model name | HP | Points |
| --- | ---: | ---: |
| `Drooling Zombie` | 90 | 1 |
| `weird monster thing` | 160 | 3 |
| `creepyMonster` | 320 | 5 |
| `creepyMonsterOrange` | 420 | 10 |
| `creepyMonsterWhite` | 520 | 15 |
| `Monster` | 430 | 5 |
| `Fouke Monster` | 230 | 3 |
| `Smiler` | 800 | 10 |
| `Brown Skinwalker` | 400 | 5 |

Fortress bosses are identified by a `Zombie` Humanoid child and use 800 HP / 15 points.

### Creepy variants

- Keep the outer model names exact: `creepyMonster`, `creepyMonsterOrange`, and `creepyMonsterWhite`.
- Do not rename nested `Noob`, Humanoid, mesh, or other legacy descendants.
- Intended damage against either players or eligible lower-HP monsters: black 60, orange 120, white 240.
- Creepy AI should prioritize nearby players. Monster infighting is deliberately rare: a 10% hunt opportunity every 20–35 seconds, lasts 5 seconds, and strikes monsters no more than once every 3 seconds.
- A creepy may hunt only a monster with lower configured HP. Same/higher HP monsters are never targets. This avoids a start-of-round creepy-versus-zombie genocide while retaining occasional fights.
- The old per-creepy `Follow` scripts scan all Workspace models continuously and old `Damage Script`s damage any touched Humanoid. They are both a behavior bug and a performance risk; do not re-enable them when `CreepyMonsterSystem` is active.

### Zombies

- `Drooling Zombie` models are managed by the central `ZombieAISystem` plus `ROBLOX_ZombieAI`.
- Only one `ZombieAISystem` Script should be enabled. A legacy duplicate was renamed `ZombieAISystemLegacy` and disabled in Studio.
- Zombie AI must target only Player characters, never other NPCs. The shared module’s target selection was changed for that purpose.
- A dead monster must not keep dealing touch damage. `MonsterDeathSafetySystem` freezes/neutralizes dead monster parts and scripts.

## Weapons and feedback

### MonsterGun

- The active server damage owner is `MonsterGunDamageSystem`, not `ServerStorage.MonsterGunServer`.
- It deals 20 damage, records score via `MonsterManager.recordPlayerDamage`, shows `current / max` hit points, and flashes the entire hit monster pink Neon for 0.25 seconds.
- Lethal kills use pink disintegration, except `BombMonster`: weapon damage lets `MonsterBombSystem` detonate it normally and it respawns through the round lifecycle.
- Gun client beam is pink and is only a brief visual. Client visual/input code must remain a Tool `LocalScript`.

### MonsterBlaster

- Keep one canonical `ServerStorage.WeaponTemplates.MonsterBlaster` Tool, with its ServerScript, LocalScript, `ShootEvent`, `ChargeEvent`, WeaponHud, `AmbientLoop`, and `Shockwave` children. The template is the source for world pickups; do not put another enabled Tool-local respawner in it.
- `src/ServerStorage/WeaponTemplates/MonsterBlaster.rbxm` and `.rbxmx` are legacy exports, not the canonical source for this Tool. Do not import their embedded old scripts over the current `.luau` files.
- Only one active world pickup should exist. `MonsterBlasterSpawnSystem` owns a `Workspace.WeaponSpawnPoints` Part whose `WeaponName` is `MonsterBlaster`; remove accidental duplicates carefully only after that spawn is confirmed in Play.
- Its server Script validates hold time, cooldown, hits, and damage. Direct damage is 40–420, with a full charge piercing monsters until map geometry blocks it. Ground shots are emergency shockwaves scaling from 40–120 damage and 6–20 studs. Hit monsters briefly flash blue Neon for 0.25 seconds.
- AmbientLoop is local to the equipped owner and stops on unequip. Shockwave is server-triggered at the validated impact so nearby players hear it.
- The charge HUD uses `ResetOnSpawn = false`, so the Blaster client must explicitly hide/reset it on unequip, respawn, or whenever the Tool is no longer equipped.
- Do not make bombs damage/explode each other. Player weapon damage may detonate a `BombMonster`, but must not mark it permanent; it returns only while its normal finite round lives remain, keeping the round clearable.

### Legacy marketplace-model revival

- Treat every imported model as an unknown integration, not as a conventional Roblox asset. Its visible control can be entirely client-driven while `Seat.Occupant`, `Humanoid.SeatPart`, character position, model pivot, and even the advertised hierarchy are absent, stale, or unrelated on the server.
- Start with one narrow live-Play evidence loop: log the client action, the RemoteEvent receipt, and the server's exact terminal result (`hit`, `blocked`, `miss`, or rejected reason). Do not add seat/range/attribute ownership gates until the active model proves that data actually replicates. Keep proven useful, rate-limited diagnostics in place until the user asks to remove them.
- When strict ownership data is unavailable and the model is a low-stakes map prop, prefer a deliberately forgiving compatibility bridge: keep the server responsible for monster lookup, damage, score, death handling, and a fire-rate limit; accept the legacy controller's aim point and use a small aim-point fallback when a cosmetic barrel ray is unreliable. State that choice explicitly rather than inventing unsupported server state.
- Never use Plugin-only APIs (for example `Instance:GetDebugId()`) inside a live server/client Script. Use normal Instance-keyed Luau tables for per-player/per-model state.
- For a model whose active instance/script path is unclear, use Studio AI Assistant only as a narrow, read-only audit: ask one concise question about the exact named model, active Script/LocalScript/RemoteEvent paths, and runtime instance classes. It is token-limited; do not use it for broad scene reviews, code generation, or modifications. Save its findings as comments in `ServerStorage.StudioAuditReports` and verify them in a fresh Play session.
- The verified reference is `Workspace.Machine Gun Tower.Turret` plus `ServerScriptService.TurretCombatSystem`: its legacy controller fires `ReplicatedStorage.TurretShot`, and the compatibility bridge successfully damages and scores normal `MonsterManager` monsters. Reuse the investigation sequence, not its names or hierarchy assumptions.

### Inventory, camera, crosshair, and contours

- `WeaponInventoryGuard` leaves Roblox's default Tool pickup untouched. It destroys only the newly transferred second copy of a named unique weapon, leaving the first normal Tool in the player's Backpack/Character. Do not add prompts, return-to-world behavior, pivots, or AnchorScript changes.
- There have been duplicate `WeaponRuntimeSystem` Scripts in `ServerScriptService`; keep all old duplicates **disabled**. They caused camera/tool conflicts.
- There was a `SoundManager` Script containing a misplaced client `CameraController`; it must stay disabled because `Players.LocalPlayer` is nil on the server.
- Do not leave `CameraAimSafety` active. It fights the actual controller by continuously restoring third-person camera state.
- Camera behavior: `Z` toggles persistent first person (including respawn). Holding RMB with MonsterGun/MonsterBlaster temporarily uses a close over-the-shoulder third-person view; release restores normal camera. RMB must not force permanent first person.
- Cross-platform combat input must use Tool `Activated`/`Deactivated` or a contextual touch action; mouse buttons, RMB, and keyboard keys must never be the only way to fire, charge, or release a weapon. Touch players aim with the native camera and must receive visible aim feedback. Require a real touch-device Play test before calling mobile combat fixed.
- Use the Tool’s existing `WeaponHud` and existing Crosshair element. Do not create a competing `WeaponAimHud`/second reticle.
- `WeaponTargetContour` is client-only. It outlines only direct, unobstructed, living monster targets: pink for MonsterGun, blue for MonsterBlaster. It must coexist with the red last-20-monsters contour (`MonsterContourClient`) rather than replacing it.

## Teleports and UI

- The portal system was repaired manually by copying the current teleport script into the second duplicate `Workspace.TeleportParts` folder. Do not refactor portals without first auditing both folders and their actual scripts.
- The score/monster HUD has mobile constraints: compact current score and alive-monster count belong top-right; detailed records should be collapsed/official leaderboard rather than permanently taking mobile screen space.
- `GameFlowHud.client.luau` creates the welcome/round-complete flow in code. Studio visual edits can be overwritten when it runs. If the user is editing GUI visually, preserve those changes and stop/disable the generator only with explicit direction.

## Performance and diagnostics

- A reported 3–5 FPS regression must be measured before changing code. Ask for a read-only Studio audit and View → Script Performance sorted by activity/time.
- High-risk legacy behavior already known:
  - 23 creepy `Follow` scripts with `while true` and `Workspace:children()` scans.
  - 23 creepy touch damage scripts without cooldown/target filtering.
  - legacy duplicated NPC, respawn, weapon, and vehicle scripts from old marketplace models.
  - massive repeated Output errors (missing assets, missing `HumanoidRootPart`, broken legacy models) may materially hurt Studio testing.
- Treat Roblox’s scattered asset-load warnings as separate from functional game errors; prioritize repeating server errors from active AI/weapon scripts.
- For performance fixes, start with one confirmed P0 offender, make the smallest reversible change, then measure again.

## Safe verification

- `rojo build default.project.json --output /private/tmp/forest-of-horrors-validation.rbxlx` is useful only as a local Luau/project-structure validation. It does not update the game and should not be presented as Studio validation.
- After a manual Studio paste, ask for a fresh Play session and only test the changed slice.
- Before testing camera/targeting, verify the active instances/classes/locations with a read-only Studio Assistant audit. Studio Assistant should save reports as comments in `ServerStorage.StudioAuditReports`, never modify gameplay scripts automatically.

## Current direction

The immediate goal is a stable, playable horror survival round before ambitious systems or broad cleanup:

1. Keep monster AI responsive and prevent uncontrolled NPC self-killing.
2. Make gun/blaster damage, health feedback, death behavior, and BombMonster detonation/respawn reliable.
3. Keep portals functioning without broad rewrites.
4. Improve mobile-safe HUD and game flow only after the base loop is stable.
5. Reduce actual measured performance bottlenecks, beginning with legacy per-NPC loops and repeat error spam.
