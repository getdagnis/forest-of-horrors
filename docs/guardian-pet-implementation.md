# Guardian pet / gang leader implementation

## Ownership and installation

`ServerScriptService.GuardianMonsterSystem` remains the only WMT movement owner.
It delegates bonded pet/gang decisions to `GuardianTactics` and Humanoid routing
to `GuardianNavigation` (two sibling ModuleScripts). Unbonded help, adoption,
hostility, appearance, health, radar attributes and death ownership stay in the
existing system. No new packages or competing AI loops.

`ReplicatedStorage.MonsterManager.recordPlayerDamage` records
`LastPlayerDamageAt` for recent-owner-target assistance. Damage still uses
`damageMonsterTarget`; this update does not introduce pet-kill score rewards,
permanent deaths, extra monster lives or monster-count changes.

`StarterPlayer.StarterPlayerScripts.WMTRescuePrompt` displays the optional
server-owned `WMTGuardianStatus` RemoteEvent. Small quoted white messages appear
above the hotbar for four seconds. Conversation, acceptance and loss notices
take precedence. No player-to-server tactical command remote was added.

## Behavior and tuning

All tactical settings live in `GuardianTactics.Config`:

- 14-stud escort offset, 18 walk / 26 catch-up / 28 combat speed.
- Threats within 10 studs of owner interrupt distant assists. Otherwise assist
  the owner's recently hit target, defend the 30-stud area, then clear locally.
- 150-damage strikes, 0.65-second guardian-wide cooldown, 9-stud horizontal
  reach and 8-stud root-height allowance for the tall WMT rig. Collision-aware
  line of sight is required. Transparent collidable glass blocks hits.
- Moving targets get short velocity-led approach destinations, not root-to-root
  touch chasing. Targets receive a short commitment lock to prevent jitter.
- Two failed navigation attempts or ten seconds without a successful hit cause
  recovery / target abandonment. Failed targets are excluded for twenty seconds.
- Owner beyond 200 studs: hold a local 80-stud hunting area. A returning owner
  within reach resumes escort. Failed owner routes retry after eight seconds,
  or sooner when the owner moves significantly. A new Character resets the
  route, not the owner bond. No monster teleport, pivot correction or force boost.
- Up to three gang followers. Existing 70% invitation / 120-second membership /
  180-second post-membership cooldown / 30-second decline retry remain.
  Active conversations and normal help assignments cannot be recruited away.
- Gang members copy the leader's target, approach from separate slots, and use
  independent cooldown/recovery. Dead, expired or excessively distant leaders
  cause release to normal WMT behavior.

Navigation tracks feet rather than treating the elevated WMT root as a ground
waypoint. Agent height is derived from the collidable rig. It checks jumps,
blocked waypoints, actual progress and ground support; at most three asynchronous
path computations run together. Old path results cannot overwrite a reset route.

Status messages describe Follow, Cover, Engage, Recruit, Regroup, HoldAndHunt and
Recover. They are event-driven, not generated dialogue: at most one message per
eight seconds, with a thirty-second cooldown per state phrase.

## Validation / next playtest

`tests/GuardianTactics.studio.luau` is an isolated Studio server Play harness,
not a production Script. It creates its own floor, cloned rigs and owner markers,
strips fixture scripts/sounds/old BodyMovers, and removes its fixtures afterwards.
Only fixture initial placement uses PivotTo, before parenting into Workspace.

Checks cover tall-rig follow/arrival, base and stronger-generation damage,
character replacement, distant-owner hunting/rejoin, glass obstruction,
failed-target exclusion, routing around glass, moving-zombie interception,
gang expiration, canonical MonsterManager damage and status rate limiting.

Latest clean-session run: 15/17 assertions passed. Escort movement worked but
the five-second test deadline ended before the Cover-state assertion passed.
The moving-zombie interception check did not achieve a kill within its eight-
second window. Earlier fixture runs were contaminated by copied avoidance
forces and overlapping corpses; do not use those as gameplay evidence.
Automated testing stopped at the creator's request. Moving-target pursuit and
escort settling remain explicitly unverified; the temporary Studio test runner
was removed. No claim of complete map-wide behavior verification is made.

Still require normal gameplay validation: the complete adoption ritual followed
by actual player respawn, multiple players recruiting simultaneously, the exact
McDonald's tables/windows and underground routes, and mobile status readability.
Passing an isolated arena does not prove every legacy map passage is traversable.

The pre-update live scripts are retained in
`ServerStorage.GuardianBeforeTactics_20260906` (Script copies disabled).
Do not enable backup AI alongside the active controller. Studio changes are not
published by this workflow; repository files remain the manual code backup.
