# Test-session change register

This is the handoff list for manual Roblox Studio updates and Play-session
observations. The live Studio place is authoritative. A repository file is a
draft/backup until its matching Studio instance has been manually replaced and
tested in a fresh Play session.

## Current rule

- Add live observations here first; do not turn them into a source or Studio
  change until they are placed in an approved batch.
- Keep each batch small and test only that slice.
- For every manual paste, mark its row `Pasted` and record the Play result.

## 2026-08-15 implemented backup handoff — not Studio-validated

The following source is now prepared. Paste **one numbered batch at a time**,
start a fresh Play session, and record its result below before moving on.

### 1. Round integrity and deadline

- Replace `ServerScriptService.MonsterSystem` from
  `src/ServerScriptService/MonsterSystem.server.luau`.
- Replace `ServerScriptService.MonsterDeathSafetySystem` from
  `src/ServerScriptService/MonsterDeathSafetySystem.server.luau`.
- Replace `ServerScriptService.ZombieAISystem` and
  `ServerStorage.ROBLOX_ZombieAI` from their matching source files.
- In Studio set `Workspace.MonsterMaxCount` to the map's real intended maximum
  (90 is the current source fallback). Optional navigation anchors:
  `ZombieMcDonaldsCenter=true` and `ZombieAppleCenter=true` on appropriate
  Parts/Models.
- Test: original plus two resurrections only; stale unreachable zombies retire;
  count reaches zero; 30:00 failure panel and Quick Restart work.

### 2. Combat, energy, and Blaster pickup stability

- Replace `ReplicatedStorage.GunAim` and `ReplicatedStorage.GunAimConfig`.
- Replace `ServerScriptService.MonsterGunDamageSystem` and add
  `ServerScriptService.LaserEnergySystem`.
- Replace the active canonical MonsterBlaster Tool's `ServerScript` from
  `src/ServerStorage/MonsterBlasterServer.server.luau` and its `ClientScript`
  from `src/ServerStorage/WeaponTemplates/MonsterBlasterClient.luau`.
- Replace `ServerScriptService.MonsterBlasterSpawnSystem`.
- In Studio disable old Tool-local `AnchorScript`, `GunSpawner`, and
  `MonsterBlasterGunSpawner` copies on the canonical Tool/world copies.
- Add `Workspace.EnergySpawnPoints` with BaseParts named `SmallEnergy` and
  `LargeEnergy` (or an `EnergyType` attribute); optional `EnergyAmount` numeric
  attribute overrides 100/300. Pickups respawn after 60 seconds.
- Test: no pickup teleport; MG1–MG3 never fire backwards in the kitchen;
  shared 600 energy, MG costs 1 per ray, Blaster costs 5 per fired release;
  a Smiler cannot regenerate for five seconds after Blaster damage and dies to
  two full shots within 30 seconds.

### 3. HUD, score records, radar, and health feedback

- Replace `StarterPlayer.StarterPlayerScripts.ScoreGui`, `GameFlowHud`, and
  `MonsterRadar` LocalScripts.
- Add `MonsterMilestoneHud` and `MultikillHud` LocalScripts from their matching
  source files.
- Test desktop hierarchy; Samsung Galaxy A15 landscape top-right equal badges;
  personal Best Spawn; left server board; countdown; red/green health feedback;
  adaptive radar and warning behaviour.
- At viewport widths below 1024 pixels, the server board starts collapsed behind
  `[SCORE]` and toggles to `[HIDE]`; the five combat badges remain visible.
  `ScoreGui` uses `DisplayOrder = 0`; `GameFlowHud` uses `DisplayOrder = 10` so
  welcome/round-flow overlays appear above combat UI.
- On compact landscape/mobile layouts, `ScoreGui` uses the full screen inset and
  anchors the top-right badge bar at 12 pixels from the physical screen top,
  aligned with the Roblox UI while using the clear right-side space. Mobile
  cards read left-to-right as Health, Remaining, Monsters Left, Kills (Score),
  then the red rank/round-score card on the far right.
- `GameFlowHud` is now manual-only: it was removed from `default.project.json`
  so Rojo cannot overwrite the Studio instance. The legacy welcome is hidden
  unless `ReplicatedStorage.EnableLegacyWelcome` is explicitly true.

### 4. Weird monster thing pets

- Replace `ServerScriptService.GuardianMonsterSystem`.
- Add `StarterPlayer.StarterPlayerScripts.WMTRescuePrompt` LocalScript.
- The server creates `ReplicatedStorage.WMTRescueOffer` and
  `WMTRescueResponse`; do not create duplicate remotes manually.
- Test rescue attribution, 15-stud wait, 50-stud safety gate, accept/decline,
  slow following, no instant heal at 480 MaxHealth, and shield cooldown.

### 5. Mid-term radar towers (only after 1–4 are stable)

- Add `ServerScriptService.RadarTowerSystem` and
  `StarterPlayer.StarterPlayerScripts.RadarTowerHud`.
- Mark each real tower/cockpit Model or console Part with `RadarTower=true` and
  name its usable BasePart `RadarConsole`.
- Set `Workspace.RadarMapMin` and `Workspace.RadarMapMax` Vector3 attributes
  to the true map bounds. The HUD uses a fallback only until these are set.

## Next approved paste batch

Use batch 1 from the implemented backup handoff above. Do not combine it with
later batches, and do not treat a source build as proof that the Studio place
is working.

### Mobile HUD verification blocker

- A tester reports **no visible mobile HUD change** after the published
  `ScoreGui` update on a **Samsung Galaxy A15 in landscape**. Do not tune
  mobile sizing yet.
- Before the next HUD paste, verify in Studio that the active LocalScript is
  exactly `StarterPlayer.StarterPlayerScripts.ScoreGui`, that no second
  `ScoreGui`/legacy HUD LocalScript is creating the visible badges, and that
  the published experience includes the same version that was tested locally.
- Capture one mobile screenshot after that audit. Only then adjust the
  top-right alignment and equal badge sizing.

## Files currently prepared in the backup

| Status | Repository file | Replace/add this Studio instance | Purpose | Fresh Play evidence required |
| --- | --- | --- | --- | --- |
| Draft | `src/ServerScriptService/MonsterSystem.server.luau` | `ServerScriptService.MonsterSystem` Script | Monster-count milestones and five-second multikill scoring/announcement events. | Round threshold behaviour, score attribution, multikill timing. |
| Draft | `src/StarterPlayer/StarterPlayerScripts/MonsterMilestoneHud.client.luau` | Add `MonsterMilestoneHud` LocalScript under `StarterPlayer.StarterPlayerScripts` | Purple centre `90 MONSTERS LEFT!` style milestone display and optional sound lookup. | Visual, thresholds, sounds supplied by user. |
| Draft | `src/StarterPlayer/StarterPlayerScripts/MultikillHud.client.luau` | Add `MultikillHud` LocalScript under `StarterPlayer.StarterPlayerScripts` | Multikill announcement display and optional sound lookup. | Double/triple kills and five-second chain expiry. |
| Backup mapping only | `default.project.json` | No Studio instance; documentation only | Records intended paths for the two new HUD LocalScripts. | None; do not paste this file into Studio. |

## Existing systems: replace only when their dedicated batch is approved

| Repository file | Studio instance | Batch / reason |
| --- | --- | --- |
| `src/ServerStorage/MonsterBlasterServer.server.luau` | Active canonical `MonsterBlaster` Tool > `ServerScript` | P0 pickup/equip teleport investigation. |
| `src/ServerScriptService/MonsterBlasterSpawnSystem.server.luau` | `ServerScriptService.MonsterBlasterSpawnSystem` | P0 pickup ownership; must be tested with the Tool server script. |
| `src/StarterPlayer/StarterPlayerScripts/ScoreGui.client.luau` | `StarterPlayer.StarterPlayerScripts.ScoreGui` | HUD desktop/tablet/mobile layout batch. |
| `src/StarterPlayer/StarterPlayerScripts/MonsterHudClient.client.luau` | `StarterPlayer.StarterPlayerScripts.MonsterHudClient` | HUD duplicate-count retirement; paste only with ScoreGui. |
| `src/StarterPlayer/StarterPlayerScripts/MonsterRadar.client.luau` | `StarterPlayer.StarterPlayerScripts.MonsterRadar` | Radar forward-sector and visual layout batch. |
| `src/ServerScriptService/ZombieAISystem.server.luau` | `ServerScriptService.ZombieAISystem` | Late-round zombie pressure investigation; do not alter until measured. |
| `src/ServerStorage/ROBLOX_ZombieAI.luau` | `ServerStorage.ROBLOX_ZombieAI` ModuleScript | Late-round zombie pressure investigation; do not alter until measured. |

## Live-test observations and accepted requirements

### Gameplay / AI

- **P0:** MonsterBlaster can pull a player back toward the treehouse/world
  spawner on pickup/equip; a smaller snap can also occur nearby.
- A monster may spawn originally and resurrect **at most twice**: maximum three
  lives total per round. After its second resurrection, it must remain dead for
  that round and must not be scheduled for another respawn.
- **P0 round-count bug:** Lava-pool zombie spawning is confirmed deactivated,
  yet the alive zombie/monster count still appears unable to fall below roughly
  60–75, despite an estimated 400–500 kills. This is not the 90%-remaining
  announcement threshold: investigate every *other* active respawn/spawn owner,
  including the per-death respawn path, before tuning milestones. The
  verification target is a monotonic long-run reduction once the configured
  finite lives are consumed; no hidden source may maintain a floor near 60.
- **P0 late-round integrity audit:** At about 61 minutes with 44 shown alive,
  an increasing number of zombies were stale/inactive, failed to pursue players,
  and some could not be damaged by guns. Some may be resurrected copies left in
  a floor/food-area location. Audit the live place to determine whether these
  instances are included in the alive count and whether it is possible to reach
  zero. A counted monster must be alive, damageable by weapons, able to acquire
  a player target and move toward that target; otherwise it must be repaired or
  excluded from the count and safely cleaned up. Record model path, spawn owner,
  Humanoid state/health, active AI scripts, and weapon-hit result for each
  inactive example.
- Around 30 minutes, after the centre is cleared, especially zombies become
  lethargic/passive and the map feels empty despite roughly 63 monsters alive.
  The intended fight curve grows in intensity, not fades away. First measure
  positions, target states, stuck monsters, and player contact before changing
  AI or round flow.
- **`weird monster thing` (WMT) behaviour — supersedes the earlier guardian
  proposal:** unbonded WMTs keep their current strange behaviour: they stand
  over players and appear to try to hurt them, but cannot harm players. Keep
  that intentionally weird interaction. Upgrade only their passive damage to
  nearby *other monsters*; unbonded WMTs must not create a player forcefield or
  become active protectors.
- **WMT pet offer:** if another monster attacks a WMT, the player kills that
  attacker, and the WMT survives, that WMT looks at the rescuing player and
  approaches. If the player has not killed it by the time it reaches 15 studs,
  it stops and waits. Show `This weird monster thing wants to become your pet`,
  with `[Accept]` and `[No way!]`, only after no aggressive monster is within
  50 studs of the player. This requires server-side event ownership so the
  offer cannot be forged or awarded for an unrelated kill.
- **Accepted WMT pet:** follows its owner at its own slow speed; attacks other
  monsters that are attacking the owner or are within 20 studs of the owner,
  except other WMTs. On acceptance, raise its **maximum** HP to 480 while
  retaining its current damaged health—no instant heal; recovery remains gradual.
  Only an accepted pet gains the 30-second player forcefield capability while
  hovering above its owner. Carry forward the prior threat gate (three or more
  aggressive monsters within 15 studs) and 40% activation chance unless later
  testing changes those values; add cooldown/expiry protection against loops.
- **Death feedback and cleanup:** every monster death should visibly flash
  twice, then disappear promptly. Creepy monsters currently appear frozen for
  roughly 3–5 seconds after death; reduce that post-death presence as part of
  the same shared death-effect pass, without leaving dead Humanoids able to
  attack or interfere with targeting.

### 2026-08-15 source-only count and crowd audit

This audits the backup source, **not the active Studio place**.

- `MonsterSystem.countLivingMonsters()` counts every Workspace Model recognised
  by `MonsterManager` whose canonical Humanoid has `Health > 0`. It does not
  require a root part, working AI, movement, a player target, damageability, or
  a registered respawn owner. A living but stale/unhittable configured model can
  therefore remain in the displayed count.
- The current death path has `RESPAWN_CHANCE = 0.8`. Each eligible clone is
  registered for that same path, so there is no finite original-plus-two-
  resurrections limit. This directly explains why long rounds can keep
  replenishing instead of approaching zero.
- Respawn positions come from the monster model's stored spawn CFrame. A bad or
  stuck original spawn position repeats on every resurrection, consistent with
  recurring stale monsters in one area.
- Zombie AI deliberately alternates Idle/Search from `ChanceOfBoredom` and
  `BoredomDuration`; it does not actively discard an unreachable pursuit target.
  This can strand a zombie after a path failure. Confirm this in Studio.

#### Small, high-impact recommendations (after the Studio audit)

1. **Finite-life ledger before cloning:** each original gets two remaining
   resurrections; decrement only when one is scheduled; clones inherit the
   remainder. At zero, destroy after the two flashes and never queue a clone.
2. **Managed/countable invariant:** count only a living server-managed monster
   with its canonical Humanoid and root part. On a low fixed cadence, repair or
   remove managed monsters that are dead, rootless, or cannot receive weapon
   damage; never merely hide an active monster from the count.
3. **Stuck-target recovery:** after several seconds without meaningful movement
   while a living player exists, clear the stale target and reacquire a reachable
   player. One failed retry should safely return/replace the monster rather than
   leaving it counted forever.
4. **Late-round pressure director:** only after count integrity, periodically
   retarget a capped number of the furthest/idle zombies toward active players.
   It improves encounter rate without map-wide teleporting or an unbounded pile.

5. **Slow centre gravity for all monsters:** outside the broad central region,
   every monster receives a very weak, varied navigation bias toward the map
   centre around McDonald's. It is deliberately slow and indirect: a monster
   may take roughly 10–30 minutes to arrive, rather than marching in a visible
   straight line. Once within 200 studs of that region, remove the centre pull;
   the monster should casually browse/hunt for player targets there, not crowd
   onto McDonald's itself. Combat pursuit, stuck recovery, and guardian rules
   override this background bias when active.

6. **Zombie idle home and swarm spacing:** when a zombie has no better action
   and no player is nearby, bias it toward casually hanging around the Apple
   Center, including a deliberately limited number indoors. When players are
   nearby, player pursuit/swarming overrides that idle-home preference. Maintain
   roughly one stud of local separation between zombies so a pursuing crowd
   remains visibly individual rather than merging into one green mass.

Required Studio evidence: inspect at least three stale examples and record full
model path, attributes, canonical Humanoid health, root state, `CentralZombieAI`
attribute/active scripts, last movement, count inclusion, and MonsterGun hit
result.

### Combat aiming

- Desktop aim helpers (target contours and MonsterBlaster blast radius) appear
  only while focused aim is active.
- **P0 barrel-direction invariant:** a MonsterGun ray/beam must never leave its
  barrel at 90 degrees sideways or backwards. This is currently most visible on
  MG2 and MG3 in constrained spaces such as the McDonald's kitchen. Before a
  shot, resolve the character/tool facing toward the selected aim direction;
  only a small sideways deviation is permitted as a last-resort fallback when
  movement/turning is physically constrained. Apply the same forward-cone rule
  to the client visual and the server-validated shot direction, so a visually
  forward beam cannot damage something behind the barrel (or vice versa).
  Verify in close walls, doorways, and the kitchen with MG1–MG3.
- Late-round monster contours are an exception to focus-only helpers: when the
  authoritative alive-monster count reaches **40 or fewer**, automatically show
  contours for eligible monsters within **200 studs**. This replaces the older
  last-20-monsters threshold.
- Mobile aiming and helper behaviour remains a separate design/test task.

### Laser-weapon energy

- All laser guns use exhaustible energy. This covers MonsterGun variants and
  MonsterBlaster; it does not imply an energy system for non-laser weapons.
- Add two map pickup types: **small energy** restores 100 standard gun shots;
  **large energy** restores 300 standard gun shots.
- A MonsterGun shot costs one energy unit. Every MonsterBlaster fired shot costs
  five energy units, whether released at 1% or 100% charge ratio.
- Required design values before implementation: each weapon's starting energy,
  maximum capacity, whether energy is shared between all laser guns or stored
  per weapon, and whether any passive recharge exists. Until decided, do not
  infer a recharge mechanic.

### Monster balance

- Smiler monsters appear to regenerate health fast enough that a MonsterBlaster
  loses its intended advantage during its charge/cooldown gap. Acceptance target:
  two 100%-charged MonsterBlaster shots, delivered within a reasonable sequence
  of less than 30 seconds, must kill a Smiler.
- The implementation may raise full-charge Blaster damage, suppress/delay
  Smiler regeneration after Blaster damage (for example, for five seconds), or
  combine both. Choose the smallest server-authoritative change after measuring
  the current Smiler regeneration rate; do not weaken ordinary MonsterGun
  viability as a side effect.

### Player health feedback

- Every time the local player loses health, play the `PlayerHurt` sound and
  briefly flash a red full-screen overlay. Scale overlay opacity from 2% to 30%
  by the seriousness of the hit: damage as a percentage of the player's
  immediately previous remaining health, clamped to that range.
- Every time the local player gains health, flash a greenish overlay twice and
  show a greenish floating/message text such as `+23 HP restored`, using the
  actual health restored after max-health clamping.
- Implement this from replicated Humanoid health changes so monster attacks,
  environmental damage, and all healing sources receive the same feedback;
  avoid duplicate feedback when one health change is observed by more than one
  client script.

### HUD and radar

- Desktop: retain five-card combat HUD; rank card is strictly screen-centred
  and visually dominant.
- Each round has a **30-minute limit** to kill all monsters. Replace elapsed
  `GAME TIME` display with a countdown labelled `REMAINING`, for example
  `3:21 REMAINING`. Monster completion must occur before `0:00`; connect expiry
  to the existing round-flow failure/restart outcome rather than allowing the
  round to continue silently past the limit.
- Add a full server scoreboard on the left, directly below the original Roblox
  HUD. It is separate from the compact combat HUD and lists all current server
  players in rank order. Format each entry as bold `1. rainbbbow_friend:
  72/44 (89)`, meaning `[score]/[monsters killed] ([best score this game])`.
  Render the local player's own name in dim yellow.
- At the bottom of that list, add an all-time record block:
  `All time best:` followed by `rainbbbow_friend: 182` on the next line.
- The far-right **Best Spawn** badge shows the player's highest score earned in
  any one spawn during the current game/session. It is not a label-only change,
  not a global top score, and must not show the current spawn number (for
  example, `1`).
- Tablet: reduce wasted space so the HUD fits the original top GUI level.
- Mobile: align the complete HUD top-right; all stat badges are the same size.
  Do not apply the desktop enlarged rank treatment.
- Remove the old `Monsters: ...` counter once the replacement HUD is active.
- Radar: top-right circular dark/translucent background; player centre light
  blue; monsters red; 50-stud local range; a transparent blue **sector** points
  toward the camera/player's forward direction. Player dots are optional, not
  approved yet.
- Radar danger warning: when any creeper-family monster or Fortress Boss enters
  the radar range, play a warning signal once for that entry. Their radar dots
  are twice the normal monster-dot size to communicate danger. Track entry/exit
  state and apply a short re-entry cooldown so the warning cannot fire every
  radar refresh while a monster remains at the range boundary.
- Radar range is adaptive, clamped from 30 to 100 studs. Priority order:
  1. If 10 or more monsters are within 50 studs, use a 30-stud radius.
  2. Otherwise, if one to nine monsters are within 50 studs, use 50 studs.
  3. If none are within 50, expand to 60; if none are within 60, expand to 70;
     continue in 10-stud steps through 100, stopping as soon as a monster is
     found or at the 100-stud maximum.
  This is the actual radar/dot scale, not merely a cosmetic zoom.
- If the radar has expanded to 100 studs and still has no monster dot, locate
  the nearest monster beyond that radius and brighten the corresponding segment
  of the outer circular rim. This is a directional out-of-range cue only; do
  not show a misleading in-range dot or enlarge the radar beyond 100.
- Health bands should use the supplied purple/blue/green/olive/yellow/ochre/
  orange/red palette.
- Monster-count card shows delta across a tunable recent period (initially ten
  seconds), for example `(+2)` or `(-12)`.

### Announcements and scoring

- At every remaining-monster multiple of ten, starting only after the round is
  at least 10% below its configured map maximum, announce `90 MONSTERS LEFT!`
  in large purple centre HUD text. The user will provide sounds for 90 through
  10.
- Multikill base score should be the sum of the killed monsters' original
  values, plus a bonus equal to the number of monsters in the same shot or a
  five-second kill chain.
- Required decision before implementation: announce a multikill immediately as
  the chain grows, or settle/show it only after five seconds without a kill.
- Required decision before implementation: map maximum must be an explicit map
  configuration value, not merely the count observed at round start.
- Required decision before implementation: preserve current shared-damage
  score splitting, or award each lethal shooter the full original monster value.

## Sound assets to add later

- `SoundService.MonsterMilestoneSounds`: Sounds named `90`, `80`, ... `10`.
- `SoundService.MultikillSounds`: proposed names `DoubleKill`, `TripleKill`,
  `QuadKill`, and `MegaKill`.
- These folders are optional until audio files are supplied; HUDs should remain
  silent rather than error when a sound is absent.

## Mid-term backlog — do not include in the current implementation batch

- **Radar towers:** identify roughly four existing tower cockpits/radar stations
  near the map corners. When a player enters and uses one, show a dedicated
  full-map HUD with the current locations of all monsters. This is a map-object
  interaction with a separate UI, not an expansion of the player’s compact
  30–100-stud personal radar. First audit the actual tower models, cockpit
  interaction points, and any existing machine-gun-tower scripts before design
  or implementation.

## Session result log

| Date / batch | Studio instances updated | Play result | Output errors / notes |
| --- | --- | --- | --- |
| 2026-08-15 / planning | None | Not applicable | This document was created; no gameplay source was pasted. |
| 2026-08-15 / published ScoreGui | Reported `ScoreGui` update | Failed mobile verification | Samsung Galaxy A15, landscape: tester reports no visible mobile HUD changes. Verify the active instance and published version before a new layout edit. |
| 2026-08-15 / implementation backup | Batches 1–5 prepared in source | Static-only pass | `git diff --check` and `rojo build` pass; no fresh Studio Play evidence yet. |
| 2026-08-16 / bomb respawn root repair | `ServerScriptService.MonsterSystem` | Pending fresh Play test | `BombMonster` has no `HumanoidRootPart`; the watchdog previously retired it as a permanent missing-root kill before its 120–270s self-destruct/respawn path. It now accepts its `PrimaryPart`/first body part as the root. |
| 2026-08-16 / focused Blaster aim repair | `ReplicatedStorage.GunAim`; `ServerScriptService.MonsterGunDamageSystem`; canonical `MonsterBlaster` Tool `ServerScript` and `ClientScript` | Pending fresh Play test | Ground preview, client payload, and server combat now use the camera/crosshair ray. Muzzle/barrel remains the visible beam and short clearance origin only; it no longer clamps the selected impact point. |
| 2026-08-16 / Blaster feedback + contour grace | `ReplicatedStorage.GunAimConfig`; `StarterPlayerScripts.WeaponTargetContour`; `ServerScriptService.MonsterGunDamageSystem`; canonical `MonsterBlaster` Tool `ServerScript` and `ClientScript` | Pending fresh Play test | Restores the Tool's own Crosshair and removes the custom blue centre dot. Ground shockwave preview appears only after one second continuously aimed at valid ground. A server-validated, 0.20-second contour cache now survives normal Studio/camera timing while still checking live line-of-sight before damage. |
| 2026-08-16 / health feedback threshold | `StarterPlayerScripts.ScoreGui` | Pending fresh Play test | Green `+HP restored` text and flashes now require a single health increase of at least 10 HP; automatic +1 regeneration remains silent. |
| 2026-08-16 / Blaster reticle + orange creepy stabilization | Canonical `MonsterBlaster` Tool `ClientScript`; `ServerScriptService.CreepyMonsterSystem` | Pending fresh Play test | Replaces the incorrectly positioned legacy Blaster HUD crosshair with a centred four-line reticle. Removes legacy force movers from `creepyMonsterOrange`, assigns its root to the server, and clears runaway spin/upward velocity. |
| 2026-08-16 / calmer unbonded WMTs | `ServerScriptService.GuardianMonsterSystem` | Pending fresh Play test | Unbonded WMTs no longer hurt every monster they touch. A player health loss makes each WMT within 200 studs independently respond with 30% chance for six seconds; it can defend only threats within 20 studs of that hurt player. |
| 2026-08-16 / deliberate linear Blaster charge | `ReplicatedStorage.MonsterBlasterConfig`; canonical `MonsterBlaster` Tool `ServerScript` and `ClientScript` | Pending fresh Play test | Taps are cancelled without energy/cooldown. A shot requires one second of hold (about 20% of the 5.2s full charge), enforced by both client and server. Damage/power now rises linearly with hold time. |
| 2026-08-16 / Blaster blue light restoration | Canonical `MonsterBlaster` Tool `ClientScript` | Pending fresh Play test | Each valid Blaster release now creates a short local blue muzzle and impact PointLight pulse, scaled by charge. This restores environmental blue illumination without changing damage, energy, or shockwave rules. |
| 2026-08-16 / proven Blaster lights + longer gun pulses | Canonical `MonsterBlaster` Tool `ClientScript`; `StarterPlayerScripts.GunClientController` | Pending fresh Play test | Restores exact stronger Blaster PointLight values from commit `09edc2c`. MG1–MG3 retain their weapon colours but now keep muzzle/impact/beam lights visible for 0.20/0.28/0.24 seconds respectively. |
| 2026-08-16 / Light Saber coloured strike pulse | Active Light Saber Tool `SlashFlash` LocalScript | Pending fresh Play test | Restores/strengthens the saber's coloured PointLight at the blade tip: brightness 14, range 26, 0.22s lifetime. Uses `Tool.Activated`, so it also works for touch/gamepad activation. |
| 2026-08-16 / varied zombie direction + bounded infighting | `ServerStorage.ROBLOX_ZombieAI`; `ServerScriptService.ZombieAISystem`; `ServerScriptService.MonsterLure`; `ReplicatedStorage.MonsterManager` | Pending fresh Play test | Zombies are excluded from the optional global lure by default. Idle searches now pick varied local central waypoints; at most one three-zombie group may briefly harass a non-WMT, non-bomb monster. Monster player/monster damage and effective HP are centralized in `MonsterManager`; default player weapon damage remains unchanged. |
| 2026-08-16 / yellow creepy and rare zombie physics guard | `ServerScriptService.CreepyMonsterSystem`; `ServerStorage.ROBLOX_ZombieAI` | Pending fresh Play test | Orange and yellow creepy rigs have legacy force movers removed and server-owned excessive-motion guards. Zombies zero only implausible velocity/spin, preserving ordinary Humanoid pathing. If yellow remains broken, inspect its exact Studio model/scripts because it is not present in this source snapshot's canonical monster list. |
| 2026-08-16 / seated radar-tower diagnostic map | `ServerScriptService.RadarTowerSystem`; `StarterPlayerScripts.RadarTowerHud` | Pending fresh Play test | Sitting in a Seat/VehicleSeat below a `RadarTower=true` tower now opens a near-full-screen map with every living Drooling Zombie, the local player, and optional `radar_detect=true` landmarks. `RadarMapMin`/`RadarMapMax` Workspace Vector3 attributes tune the map bounds. |
| 2026-08-16 / visible laser reserve + Power Box charging | `ServerScriptService.LaserEnergySystem`; add `StarterPlayerScripts.LaserEnergyHud`; `StarterPlayerScripts.GunClientController`; canonical MonsterBlaster Tool `ClientScript` | Pending fresh Play test | A label-free cyan reserve bar animates 0.30s after accepted energy loss. Below 20% it plays `EnergyDepleted`; at zero it plays `EnergyShutdown`; empty guns and Blaster attempts use the existing no-power/cooldown sound. The named `Power Box` (or an `EnergyChargeStation=true` object) receives a charge prompt and restores 600 energy in 9s from empty, using its `BonusChargeUp` and `DING` Sounds. |
