# Forest of Horrors helper scripts

This folder contains local helpers for updating the Roblox Studio place without editing the `.rbxl` binary directly.

## Generate Studio Command Bar scripts

```sh
node scripts/generate-monster-bomb-update.js
node scripts/generate-guardian-update.js
```

Generated files:

- `generated/monster-bomb-update.lua`
- `generated/guardian-update.lua`

Copy the generated Lua into Roblox Studio Command Bar, run it, then save the place.

## MonsterBomb workflow

Run `generated/monster-bomb-update.lua` in Studio. It will:

- create/update `ReplicatedStorage > MonsterBombConfig`;
- create/update `ServerScriptService > MonsterBombSystem`;
- remove old per-model `MonsterBombScript` scripts from `Workspace` models named `Monster`;
- add hidden `Humanoid` objects to `Monster` models if missing;
- set bomb monster HP to 400;
- update `ReplicatedStorage > MonsterManager` so `Monster` has 400 HP, if it finds the existing config line.

Important model expectations:

- bomb models are named exactly `Monster`;
- warning sound is named `WarningSound` or `WarningSound1`;
- optional blast sound is named `BlastSound` or `ExplosionSound`.

Main tweak file:

- `generated/sources/MonsterBombConfig.lua`

After editing that config source, regenerate and paste `generated/monster-bomb-update.lua` again.

## Guardian monster workflow

Run `generated/guardian-update.lua` in Studio. It will:

- set `weird monster thing > Configuration > AttackDamage` to `0`;
- create/update `GuardianLegDamage` inside every `weird monster thing`.

Guardian behavior:

- does not hurt players;
- damages other recognized monsters with leg/foot parts;
- ignores other `weird monster thing` guardians.
