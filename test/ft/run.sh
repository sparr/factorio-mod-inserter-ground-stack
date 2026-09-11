#!/usr/bin/env bash
# Integration tier: build inserters in a real game and see what they leave on the ground.
#
#   test/ft/run.sh                       # headless, no display, whole suite
#   test/ft/run.sh -v                    # with the game's own log lines
#   test/ft/run.sh "quality"             # only tests matching a Lua pattern
#   test/ft/run.sh -g --no-auto-start    # open a window and pick tests by hand
#
# IGS_FACTORIO    the game binary, if it is not where Steam puts it here
# IGS_FT_DATA     the throwaway data directory the run happens in
# IGS_SPACE_AGE   set to 1 to run with Space Age on, which the space platform and Aquilo
#                 tests need. They stand aside without it, so the plain run says nothing
#                 about either.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

factorio="${IGS_FACTORIO:-/home/sparr/Games/Steam/steamapps/common/Factorio/bin/x64/factorio}"

# Without this the Steam client intercepts the launch and starts its own copy of the game,
# which is not the one being handed a mod directory and a save. The CLI launches the game
# more than once, so exporting it here covers all of them. A non-Steam build ignores it.
export SteamAppId="${SteamAppId:-427520}"

# Deliberately outside the repo: the CLI symlinks the mod under test into this directory's
# mods folder, and a data directory inside the repo would therefore make the repo contain
# itself.
data="${IGS_FT_DATA:-$HOME/.cache/igs-factorio-test}"

if [[ ! -x node_modules/.bin/factorio-test ]]; then
    echo "the test runner is not installed. Run:" >&2
    echo "  npm install" >&2
    exit 2
fi
[[ -x "$factorio" ]] || { echo "no factorio binary at $factorio" >&2; exit 2; }

# A local function used before it was defined reads as a call to a global that is nil.
# Nothing catches it until that line is finally reached, which in a mod can be minutes into
# a run on somebody's factory, so it is worth the second luacheck takes here.
if command -v luacheck >/dev/null 2>&1; then
    luacheck --quiet control.lua test/ || {
        echo "luacheck is unhappy; fix that before running the suite" >&2
        exit 2
    }
fi

# igs-tests carries no prototypes; it is the gate that keeps the fixtures from registering
# on a player's machine. It is not on the mod portal, so the CLI cannot fetch it: put it
# where the CLI looks and it will leave it alone.
mkdir -p "$data/mods"
ln -sfn "$root/test/ft/igs-tests" "$data/mods/igs-tests"

# The tests that build a space platform or stand something on Aquilo cannot run without
# Space Age, and the rest of the suite is happier without it: a vanilla game is the smaller
# world and the one most players are in. Switched on by asking rather than by default, and
# the tests that need it stand aside when it is off.
sa_args=()
if [[ "${IGS_SPACE_AGE:-0}" == "1" ]]; then
    # --mods takes a list, and a list has to be closed with -- before any test filter.
    # igs-tests is named again because --mods replaces the list in factorio-test.json
    # rather than adding to it, and without it nothing registers any tests at all.
    sa_args=(--mods igs-tests space-age quality elevated-rails recycler --)
fi

exec node_modules/.bin/factorio-test run \
    --factorio-path "$factorio" \
    --data-directory "$data" \
    --output-file "$data/results.json" \
    ${sa_args[@]+"${sa_args[@]}"} \
    "$@"
