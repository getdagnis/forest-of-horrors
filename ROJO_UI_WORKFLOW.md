# Studio UI ownership

Rojo is source-to-Studio only: it does not read visual edits back from the
Studio UI editor. If a mapped LocalScript creates its own `ScreenGui`, the
script owns that UI every time the player joins.

## Current safe boundary

`GameFlowHud.client.luau` is deliberately **not** mapped in
`default.project.json`. It is a manual-only backup script:

1. Edit the welcome/round-flow UI in Studio.
2. Do not Rojo-sync `GameFlowHud`; it cannot overwrite the Studio instance.
3. If its code must change, manually replace only
   `StarterPlayer.StarterPlayerScripts.GameFlowHud`, then test it.

The legacy welcome itself is off by default. Set the Bool attribute
`ReplicatedStorage.EnableLegacyWelcome` to `true` only when that screen is
intentionally wanted.

## Rule for future UI work

- **Code-owned UI:** keep the generator mapped and change the Luau source; do
  not edit its generated `PlayerGui` result in Studio.
- **Studio-owned UI:** keep the `ScreenGui`/LocalScript outside the Rojo project
  map and edit it only in Studio. Do not give a mapped generator the same GUI
  name.

For the current combat HUD, `ScoreGui.client.luau` remains code-owned while it
is being iterated. Move it to the manual-only boundary only after its visual
design is stable.
