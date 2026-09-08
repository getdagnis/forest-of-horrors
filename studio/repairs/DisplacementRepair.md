# Displacement repair — 2026-09-08

Applied directly to the connected Studio Edit place; no Rojo sync or publish.

## Confirmed source fault

The old `ServerScriptService.MonsterForcefieldSystem.blockModel` registered a
monster's parent whenever `parent:IsA("Model")`. Workspace satisfies that test.
`MonsterSystem` respawns monsters directly into Workspace. This could register
Workspace, assign the whole scene to BlockedMonster, and make
`getTopmostBlocked` return Workspace. The pushback loop then called
`Workspace:PivotTo(...)` using a monster position as the world pivot target.
This is a concrete whole-world displacement path, consistent with the recorded
large, zero-velocity jumps. The original recorded session was not replayed.

## Changes and Studio placement

- `src/ServerScriptService/MonsterForcefieldSystem.server.luau` replaces
  `ServerScriptService.MonsterForcefieldSystem`: collision-only barriers,
  canonical MonsterManager lookup, no ancestor promotion or pushback loop.
- `src/ServerScriptService/TeleportSystem.server.luau` replaces
  `ServerScriptService.TeleportSystem`: validate the same living character and
  surviving route after the streaming wait. Existing streaming remains enabled.
- Patched only `isInstaceAttackable` in all 11 weird-monster and 4 Smiler `NPC`
  Scripts in Workspace. Reject missing/wrong-class roots, removed targets, self,
  and zero-length ray direction. `WeirdMonsterNPC.luau` records the first repaired
  weird-monster source; other variants retained their surrounding source and
  child modules. Do not replace Smiler scripts wholesale with this file.

Original sources and disabled states are recorded in
`ServerStorage.DisplacementRepair_20260908` (17 disabled backup scripts).
GuardianMonsterSystem was already disabled; its state was preserved.

## Verification

- Fresh Studio Play: a synthetic recognized monster inserted directly under
  Workspace inside a barrier left map position unchanged (0 studs), retained
  scenery's Default collision group, and received BlockedMonster itself.
- Executed repaired target predicate: nil, missing root, wrong root class and
  removed target rejected without exceptions.
- Fresh Studio Play: McDonalds route from Workspace.OneWayEntrance13 reached
  Workspace.TeleportParts.OneWayExit with 0-stud destination error and 0-stud
  Workspace pivot displacement.
- Full-length survival round and all portal routes remain unverified.
- Post-portal observation for 10 seconds: player alive, player and Workspace
  displacement both 0 studs. Returned console output contained no matching NPC
  target errors, but was truncated; unrelated legacy warnings remain.
- Stopped Play and verified both server sources and all 15 NPC guards in Edit.

The earlier StreamingTargetRadius error came from a diagnostic read in Edit mode.
It was not an active gameplay script and no radius setting was changed.
