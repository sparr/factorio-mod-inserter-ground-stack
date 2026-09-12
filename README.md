# Inserter Ground Stack

Allows inserters to pile items on the ground after belt stacking is researched. Stacks a full inventory stack, not a belt stack, because stationary ground is more stable than moving belt.

Eggs are the exception. Anything that hatches when it spoils hatches in proportion to how many are lying there, so those are left to jam as they always did.

Works with Bob's Adjustable Inserters, Quick Adjustable Inserters and Smart Inserters: re-aim an inserter onto bare ground and it is picked up at once.

## If an inserter is not being helped

Run `/igs-rescan`. The mod learns which inserters put things on the ground from the events the game raises, and a mod that builds or re-aims one without raising anything leaves it unknown. The command reads the whole factory again and puts it right. That takes about a second on a very large save, as does researching belt stacking in the first place.

## Tests

`test/run.sh` runs every tier; add `--space-age` for the platform and Aquilo tests.
