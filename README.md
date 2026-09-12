# Inserter Ground Stack

Allows inserters to stack items on the ground after belt stacking is researched. Stacks a full inventory stack, not a belt stack, because stationary ground is more stable than moving belt.

Eggs are the exception, so you won't have a stack of 100 eggs hatching at once.

## Compatibility

Explicit support for
* Bob's Adjustable Inserters
* Quick Adjustable Inserters
* Smart Inserters

## If an inserter is not being helped

Run `/igs-rescan`. The mod learns which inserters put things on the ground from the events the game raises, and a mod that builds or re-aims one silently leaves it unknown. The command reads the whole factory again and puts it right.

## Tests

`test/run.sh` runs every tier; add `--space-age` for the platform and Aquilo tests.
