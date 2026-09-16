# MonsterLure incident — 2026-09-15

## Current Studio status

- `ServerScriptService.MonsterLure` is **disabled in the live Studio place**.
  It produces no movement and no HUD/event-feed report. This was deliberately
  parked after the late-session regressions below.
- `CreepyMonsterSystem` had an accidental stray `else` left by the attempted
  lure branch. It made the central creepy script fail to compile, so creepies
  froze with no player reaction. That branch was removed in Studio; the
  controller no longer consumes `MonsterLureDestination`.
- The latest test session was stopped. There is **no acceptance evidence yet**
  that zombie movement has returned to its earlier natural behaviour. A fresh
  Play test is required before claiming that.

## What failed

The goal was to prevent remote monsters remaining stranded in forest corners
late in a round while preserving natural local behaviour. The implementation
failed because it treated a world-level lure as movement input.

1. `MonsterLure` repeatedly assigned `MonsterLureDestination` attributes.
2. `ROBLOX_ZombieAI` consumed them as search destinations.
3. That interacted with the state machine's existing navigation refreshes,
   producing the observed **move → stop → slide → move** cycle.
4. The attempted creepy extension introduced a stray `else`, disabling the
   central creepy controller and freezing creepies.
5. The temporary lure HUD/count did not improve gameplay and distracted from
   validating movement first.

The architectural mistake was allowing `MonsterLure` to become a second source
of navigation intent. `MONSTER_AI_ECOSYSTEM.md` requires one movement owner per
monster family. A global lure must never repeatedly issue `Humanoid:MoveTo`,
supply high-frequency destinations, or make a family continually recalculate a
route toward a player.

## Evidence and limits

- Play tests showed the zombie stop/slide cycle; pre-change natural movement
  was better even though the lure did not yet solve remote stranded monsters.
- Play tests showed frozen, unreactive creepies; live inspection found the
  invalid `else`.
- A local `rojo build` passed after source edits. That validates source only,
  not live AI quality.

## Required next attempt

Do not restart from the experimental waypoint implementation.

1. Capture the working live baseline of `ZombieAISystem`, `ROBLOX_ZombieAI`,
   `CreepyMonsterSystem`, and `MonsterLure`; verify ordinary wandering,
   close-player reaction, and creepy pursuit in fresh Play before editing.
2. Keep `MonsterLure` disabled until that baseline is accepted. Do not add HUD
   or count work during the first behaviour pass.
3. Implement lure only as a **low-frequency, controller-owned idle
   preference**. It must not override a normal local goal, combat target, or
   player perception, and it must never force, teleport, drag, or slide a
   model.
4. Change zombies only. Do not touch creepies, guardians, pets, WMTs, bosses,
   or other families during the first experiment.
5. Test one early-round and one late-round case in fresh Play. Pass only if
   there is no stop/slide/snap cycle, nearby player combat wins immediately,
   remote zombies are less stranded as a side effect of their normal AI, and
   no new Output error appears.

## Non-negotiable rule

Natural, readable monster behaviour is more important than lure coverage. If a
lure setting cannot avoid visibly artificial movement, leave it disabled.
