# MonsterBlaster cleanup

- Goal: deliver one template-owned MonsterBlaster with reliable charge damage, emergency ground shockwaves, equipped-only ambient audio, and native cross-platform charging.
- Current evidence: the active draft has a five-second charge but a 0.4-second client-only cooldown and mouse-button-only input; its world replacement is Tool-local.
- Constraints: Studio is authoritative; source is copied manually; preserve the active world Tool until the replacement is verified; server validates charge, cooldown, targets, and damage.
- Touchpoints: ReplicatedStorage shared configuration, MonsterBlaster Tool server/client scripts, ServerScriptService spawn owner, default project map, AGENTS.md.
- Acceptance: 40-420 direct beam, 40-120 shockwave, full beam pierces, two-second server cooldown, touch charge/release works, and Studio handoff names every required instance.
