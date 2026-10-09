# Critter Kombat refinement

The solo AI previously issued a punch or kick every frame at close range, immediately restarting attacks when one finished. This made repeated hit stun possible. The AI now waits at the start of each round, advances more slowly, attacks on spaced decisions, occasionally guards rather than perfectly reacting, and backs out when too close. Fighters receive a short grace period after an unguarded hit; another attack during that period cannot deal damage. Hit stun is shorter so the defender can move, block, or retaliate before the next AI attack.

Five paired cowboy tech armor concepts are in `assets/source/breakroom-minigames-v2/previews/`. The player chooses a design before replacement animation sheets are produced. The existing fighter atlases remain active until then.
