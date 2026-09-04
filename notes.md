# notes

Your task is to to turn the "Baseball Bat" object into a working, clean, usable self-defense object that would go into players StartingPack.
Please inspect the existing object for any geometry, positioning, anchoring, pivot point potential issues and if necessary clean/normalize the object so it
can be safely used as one. The core idea is simple -- it's a weapon you can hit with:

1. Hiting/slashing needs to be animated action (basic ball up to down, same as lightsaber or any other classic Roblox cold weapon).
2. On an empty strike/swing it makes the Swing sound, on a successful hit versus a monster -- Hit sound (both are present as children)
3. On hitting it does 20 damage to any monster + pushes them a few studs away (same as lightsaber does), damage should be registered in appropriate server scripts (wherever Lightsaber is).
4. The difference between the bat and lightsaber essentially is just the look/model, that it makes no light effects and no sound on equipment.

Can you implement this?

It's holding it horizontally now. Looking from characters point of view -- 90 degrees counter clockwise. Should be straight up vertical. Also -- is it possible to alter the animation? Make it more expressive. Same animation duration but on hit it first brings the bat slightly backwards, as if gathering momentum, then releases the hit with a longer hit distance. So it takes the same time, but looks sharper, more powerful.

Would you be capable of such a task (answer honestly if in doubt or your confidence level about it is low and which parts of it seem tricky, I might do those parts myself then):

1. Take MGT2 tower as the MGT tower source. Duplicate it.
2. Move the to where currently MGT3 tower currently is, exact coordinates, rename it to MGT3 and delete the old MGT3 version.
3. For the part of the MilitaryGuardTower submodel that has SurfaceGui > 09 as its children, replace Text value from 02 to 03.
4. Find the ChainEntrance child in the newly added MGT3 tower and change its ChainedPort attribute from 02 to 03. Change its ChaingedPortTo attribute from 03 to 04.
5. Duplicate the new MGT3 tower, rename it to MGT4 and move it to exact position/rotation where old MGT4 tower is.
6. Delete the previous MGT4 version, and for the new one rename SurfaceGui > 09 text value to 04 chained port attribute to 04 and forward address to 05.
7. Continue until all towers between MGT3 and MGT10 have been replace with the new, customized, fixed and improved tower copy of MGT2.

› /plan is that big mac bonus actually active? i haven't noticed it with bigmacs. at least they are not disappearing after getting
  picked  up afterwards and there's no green overlay viewport flash as was intended -- same as hurt (same as roblox default on
  character death). similar for teleportation -- flashes white. also all -  getting hurt 7837535984, gaining health (separate for
  eating 6830313781 and picking up health pack - 106279113429184, Workspace.Bonuses.HealthPack) and teleport 74715602103425 -- should
  all trigger sounds (I have a bunch found to choose from already). in bonuses there will also be donuts (5HP restored, should be eat
  sound), coins (granted for killing monsters), powerup and shield bonuses). I have some draft models in Workspace.Bonuses for those
  but probably should move the final ones to server or replicated storage. multikill also should have a sound (actually i'm thinking
  to have 3 for that, one random picked). would be great to have all such environment/reaction etc. commonly and often used sound
  assignements in one place. I already have most if not all sound files for these in SoundService.

It works. Next smaller issue -- occassionally larger monsters can push the entire station away slightly (this is intended in gameplay). However, while all other parts of the station stay together after such a push, these transportation ports in MTG1 to MTG10 do not move with the station but fall off its edges. I tried to fix this by removing "Anchored=true" from them, but then they are not on the station at all. What is the proper fix to keep all ChainEntrances and ChainExits hold their places on the station when it is moved?

initial zombie ecosystem draft:

- a short, repeatable gameplay loop that feels intentional: zombies move naturally, approach at readable speeds, deaths and
  respawns make sense. i'd add: game feels perfectly balanced between moments of suspense, moments of action and moments of
  exploration, without losing any one of those completely at any given time, yet cycling through the three feelings
- in general i feel that macdonalds still needs to be a bastion that players need to defend together. monsters approaching from all
  directions as they were when mcdonalds was set as a magnet. but probably. there should be a constant pressure there. what i didn't
  like was the unified behaviour. they don't just crowd around mcdonalds, they all act as one zombie, on the exact same reasoning.
  player jumps down immediately they become one mass towards the player. easy target. there should be just a bit of randomness. yes
  attack, but not all taking the same path. a little irregularity.
- i'v distributed 12 towers in a planned way around the map and it's corners. those should somehow become local gathering centers.
  but not to the extent that every monster lives next to the tower or even tries to pre-emptively breach it. instead areas around the
  towers should feel like monster cities. mainly zombies doing their things (but actively, i hate how lethargic/passive they have
  become when not attacking the player). they should walk around the tower areas (or mcdonalds area) as if they were living normal
  active zombie lives. occassionally (quite frequently other monsters walk through, conflicts arise or don't etc. but they have
  something to do). occassionally they migrate between town centers. i really love the crawling monsters actually. due to incomplete
  implementation they cannot be killed/damaged. looks really cool when a bunch of wmts are around them attacking, actively fighting
  them. copletely harmless to the game mechanics, since neither can kill or harm neither, but livens up the map a lot, gives sense of
  ongoing action. such battles with no outcome should happen also between other types of monsters. zombies should attack other
  monsters too when they appear in range, not to the same extent as players so, perhaps 20-30% of zombies gravitate towards them. 70-
  90% for humans. and being harmless to both sides those battles should end too at some point, they should naturally get bored of
  fighting after a minute or 2 of no result and the hostile monster (one of creepyMonsters, wmts, Smilers, crawlers most likely) move
  on. and then when a player or players appear in range -- yes, they should all focus on the player. that's normal behaviour. if an
  enemy enters a village, villagers gather to fight. if a wasp approaches a bee nest, bees are alert and attack it all at once. but
  not "as one". they each choose a different attack strategy, some attack first from left, from top, from right, some keep swarming
  around the wasp looking for an opportunity to attack. of course, zombies can be just that -- zombies, pretty straight forward but
  still i'm sure that even with a zombie mind in place some natural statistical crowd mechanics should apply on how they choose to
  approach their target, no just straight all at once in one easily shootable line (while at it, note to exclude zombies from
  multikill bonuses, btw, due to this reason).
- btw i noticed that zombies quite regularly die by entering the lava pool next to mcdonalds. it's reported as (somehow) death,
  that explains big part of them.  i already have a monster blocking invisible object, will put it over the pool, that should fix it
- a huge issue we have so far is that zombie sudden forceful "dragging away". i absolutely suspect that that was our implementation at
some point when we tried to limit their numbers at some position but did that not via an algorithm for interest but by trying to
forcefully allow certain number of zombies be at a location and if their limit goes over -- they get thrown out of the territory
by dragging them away accross the map. absolutely wrong behaviour. but i noticed the same approach to a solution when i asked studio ai
to make mcdonalds a protected are from all monsters. instead of just blocking the doors it implemented that exact idiotic "solution" --
zombies that enter are artificially dragged across the map outside the mcdonald's territory. i guess goal achieved according to their
reasoning but gameplay ruined.
