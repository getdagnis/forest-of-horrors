# Monster AI ecosystem — binding gameplay contract

This is the design authority for monster behaviour. It exists to make Forest of Horrors feel like a living shared world rather than a set of NPCs being mechanically arranged around a player. When an existing legacy script conflicts with this document, preserve the contract and replace or disable the conflicting behaviour deliberately.

## Non-negotiable movement rules

- Never reposition a living monster with `CFrame`, `PivotTo`, velocity edits, forces, or a numerical area quota.
- Physical map boundaries, doors, blockers, and hazards must be physical. A monster that cannot reach a goal abandons that goal; it is never dragged somewhere else.
- Each monster family has exactly one movement owner. The world director supplies intent and destination area; that family AI chooses and follows its own path.
- A stuck monster may choose a nearby fallback destination, pause, or switch activity. It must not be teleported, killed, or retired merely for being stuck.
- Death, corpse lifetime, respawn, and retirement are separate explicitly configured states. They must not be used as movement correction.

## Shared world and local scenes

The world is shared. Activity happens around explicitly marked centres rather than one global command affecting every monster.

Each centre uses these attributes:

```text
MonsterActivityCenter = true
MonsterCenterId = "McDonalds" | "MT01" … "MT12" | "TreeHouse"
MonsterCenterProfile = "Bastion" | "Town"
MonsterCenterRadius = number
```

Centres independently choose one scene. At most one or two high-intensity scenes may run at once; every other centre continues background life.

| Scene | Duration / cadence | Behaviour |
| --- | --- | --- |
| Town life | 90–180 s | Zombies roam, inspect, wander, and form loose groups around a tower or TreeHouse. |
| Migration | 30–80 s; 90–240 s local cooldown | A small group chooses another centre. No group is transported or required to arrive. |
| Ambient conflict | 60–120 s | A capped minority of idle zombies investigate another nearby monster. This is visual life, normally no real damage, and ends by dispersal. |
| Alert | 25–60 s | A nearby player or local disturbance raises attention around one centre. |
| McDonald’s siege | 75–150 s; roughly every 4–7 min | A multi-direction push on the bastion. It is pressure, not an irresistible mass marching in one line. |

The first minutes favour exploration and observation. Suspense and local action exist continuously, but escalations are staggered. The final third of a round increases pressure without removing all exploration or background life.

## Centres and their identities

- **McDonald’s** is the primary bastion: recurring pressure from multiple directions, with routes and timing varied per participant. Doors and safety are solved with collision, never ejection scripts.
- **Military towers and TreeHouse** are town centres: active zombie neighbourhoods, routes, occasional migrations, and passing monster encounters. They must not become permanent monster piles or automatic siege targets.
- **Crawling monsters** remain ambient scene actors while their combat implementation is incomplete. They do not count as normal hostile round targets until they can both threaten and be damaged correctly.

## Zombie behaviour

Zombies are the main social population. They should look active even when no player is nearby.

1. Each zombie independently schedules its next intent and has a stable random seed or offset.
2. Intent priority is: nearby player threat, direct provocation, centre scene, investigate a local monster, migration, then local wandering.
3. While approaching a player, zombies select an individual attack slot: front, left flank, right flank, rear, wide flank, or wait. Their target is an offset around the player, not the exact HumanoidRootPart.
4. Refreshes are staggered. Zombies do not recalculate together or collapse into one navigational line.
5. Around 20–30% of eligible idle zombies may join an ambient nearby-monster conflict; player interest remains stronger (normally 70–90%). A player entering local perception interrupts this scene.
6. Ambient conflicts end naturally after 60–120 seconds: participants lose interest and choose fresh local goals.

## Other monster roles

- **Creepy variants:** mobile predators; player threat takes priority. Their rare lower-HP monster hunt remains narrowly bounded and must not create start-of-round genocide.
- **Smilers and fortress bosses:** rare, high-threat scene actors. They are full monsters, not historical exceptions, when they can attack players and be killed.
- **Bomb monsters:** moving danger. Their warnings, detonation, and damage remain distinct from ordinary melee pursuit.
- **Weird monster thing / guardians:** non-hostile guardians are excluded from the hostile count. A later rule may permanently turn a guardian hostile after the player attacks one or assaults a nearby guardian; do not implement that exception until its combat contract is separately specified.

## Per-player threat modes in one shared world

Threat mode changes how each monster weighs a specific player; it never makes a private copy of the map.

| Mode | Rule |
| --- | --- |
| Observer | Monsters rarely target the player. Attacking one creates only local retaliation from nearby monsters. |
| Explorer | Normal perception, pursuit, and local scene reactions. |
| Warrior | Almost every eligible monster that sees the player within its normal perception range strongly prioritises them. |

For the first implementation these are session-only Player attributes, chosen on join and held until the next round or respawn. They must not alter which monsters exist, their physics, or shared centre scenes.

## Counting, death, and player feedback

- The round’s **Monsters Left** and radar’s **Contacts** represent the same set: living monsters that can attack players and can be killed. Their shared canonical filter belongs in `MonsterManager`.
- Non-hostile guardians and incomplete ambient actors do not enter that set.
- Every death gets an intelligible cause: player kill, monster kill, bomb explosion, fell off map, hazard, or genuinely unknown. Never use retirement as a substitute for an unexplained live death.
- Corpse display duration and respawn duration are separately named configuration values.
- Event entries group matching events in the configured grouping window; they remain visible for the configured retention time/count.
- Zombies do not qualify for multikill bonuses merely because their ordinary crowd behaviour creates easy clusters.

## Architecture and ownership

1. `MonsterWorldConfig` (ModuleScript) holds centre profiles, scene pacing, threat-mode weights, corpse/respawn policy, and feature flags.
2. `MonsterWorldDirector` (Script) schedules centre scenes and exposes read-only intent queries. It never moves a model, edits physics, deals damage, or destroys a monster.
3. Family systems remain movement owners: `ZombieAISystem` / `ROBLOX_ZombieAI`, `CreepyMonsterSystem`, guardian system, bomb system, and any later family adapter.
4. `MonsterManager` is the canonical capability/counting layer. New fields such as `ambientOnly`, `canJoinConflict`, `canSiege`, and `playerThreatClass` live there rather than scattered name checks.
5. `SafeZoneManager` must not run an ejection/teleport loop. McDonald’s safety uses map collision and legitimate path failure only.
6. `MonsterLure` must remain disabled for any family controlled by the Director; it cannot become a second movement owner.

## Delivery order and acceptance gates

1. Remove forced movement and validate that zombies cannot be dragged across the map.
2. Add config and Director without changing active movement.
3. Mark and validate centres; observe no scene changes yet.
4. Restore natural zombie idle movement and individual approach slots.
5. Add one town-life / migration scene and test it in a full Play session.
6. Add McDonald’s siege and bounded ambient conflict.
7. Add per-player threat modes.
8. Normalise counting, deaths, corpses, respawns, events, and multikill exclusions.
9. Tune only with repeatable Play observations and Script Performance evidence.

Every stage must demonstrate these outcomes before the next one starts:

- no visible teleport, drag, snap, or forced eviction of living monsters;
- one movement owner per affected family;
- player aim, weapon damage, score, and radar remain intact;
- `Monsters Left` and radar contacts match their shared eligibility rule;
- local scenes look varied and intelligible rather than synchronised;
- Studio/Roblox Play evidence, not a source build alone, decides whether the stage is accepted.
