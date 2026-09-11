#!/usr/bin/env bash
# Every tier, in order of how long each takes.
#
#   test/run.sh              # the integration suite, then the save round trip
#   test/run.sh --space-age  # the same, with Space Age on for the platform and Aquilo tests
#
# There is no unit tier. Nothing in this mod can be answered without a running game: what an
# inserter does when the ground in front of it is taken is the whole of the subject.
#
# The demo session is not a test and is not run here; see test/demo/run.sh.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

space_age=
args=()
for arg in "$@"; do
    case "$arg" in
        --space-age) space_age=1 ;;
        *) args+=("$arg") ;;
    esac
done

echo "=== integration ==="
IGS_SPACE_AGE="${space_age:-0}" test/ft/run.sh ${args[@]+"${args[@]}"}

echo
echo "=== save round trip ==="
test/save/run.sh
