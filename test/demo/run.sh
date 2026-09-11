#!/usr/bin/env bash
# A session to look at the mod by hand.
#
#   test/demo/run.sh              # build the sandbox if needed, then open the game in it
#   test/demo/run.sh --fresh      # throw the sandbox away and build it again
#   test/demo/run.sh --headless   # build it and check it works, without opening a window
#
# Everything lives in its own directory: its own config, its own mods folder, its own save,
# its own player data. Nothing here touches ~/.factorio, so the mods you actually play with
# are not disturbed and neither is this.
#
# The sandbox has the mod, a demo mod that builds a row of worked examples, and nothing
# else. Space Age is on if the copy of the game has it, because two of the examples want it.
#
# IGS_DEMO_FACTORIO   the game binary; must be a graphical one to open a window
# IGS_DEMO_DATA       where the sandbox lives
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

factorio="${IGS_DEMO_FACTORIO:-/home/sparr/Games/Steam/steamapps/common/Factorio/bin/x64/factorio}"
data="${IGS_DEMO_DATA:-$HOME/.cache/igs-demo}"

# Without this the Steam client intercepts the launch and starts its own copy of the game,
# which is not the one being handed this sandbox.
export SteamAppId="${SteamAppId:-427520}"

fresh=
headless=
for arg in "$@"; do
    case "$arg" in
        --fresh) fresh=yes ;;
        --headless) headless=yes ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

[[ -x "$factorio" ]] || { echo "no factorio binary at $factorio" >&2; exit 2; }
install_root="$(cd "$(dirname "$factorio")/../.." && pwd)"

save="$data/saves/igs-demo.zip"
[[ -n "$fresh" ]] && rm -rf "$data"

if [[ ! -f "$save" ]]; then
    mkdir -p "$data/mods" "$data/saves"
    cat > "$data/config.ini" <<INI
[path]
read-data=$install_root/data
write-data=$data
[graphics]
full-screen=false
INI
    ln -sfn "$root" "$data/mods/inserter-ground-stack"
    ln -sfn "$root/test/demo/igs-demo" "$data/mods/igs-demo"

    # The expansion mods live in the game's own data directory and default to on. Left on
    # deliberately: two of the demo stations are about Space Age items. A copy of the game
    # without the expansion simply will not load them, and the demo mod stands those two
    # stations down.
    cat > "$data/mods/mod-list.json" <<'JSON'
{"mods":[
  {"name":"base","enabled":true},
  {"name":"elevated-rails","enabled":true},
  {"name":"quality","enabled":true},
  {"name":"recycler","enabled":true},
  {"name":"space-age","enabled":true},
  {"name":"inserter-ground-stack","enabled":true},
  {"name":"igs-demo","enabled":true}
]}
JSON

    echo "building the sandbox in $data ..."
    "$factorio" --create "$save" --config "$data/config.ini" \
        --mod-directory "$data/mods" > "$data/create.log" 2>&1
    echo "made $save"
fi

if [[ -n "$headless" ]]; then
    # Check the row actually builds, without opening anything. The demo mod does its work on
    # the first tick that has a player in the game, so this needs a server rather than a
    # --create, and a server with nobody in it needs telling not to pause.
    cat > "$data/server-settings.json" <<'JSON'
{ "name": "igs-demo", "description": "", "visibility": { "public": false, "lan": false },
  "require_user_verification": false, "auto_pause": false }
JSON
    timeout 90 "$factorio" --start-server "$save" \
        --config "$data/config.ini" --mod-directory "$data/mods" \
        --server-settings "$data/server-settings.json" \
        < <(sleep 30) > "$data/headless.log" 2>&1 || true
    if grep -qiE "^ *[0-9.]+ Error" "$data/headless.log"; then
        grep -iE "^ *[0-9.]+ Error" "$data/headless.log" | grep -v "EOF on stdin" || true
    fi
    echo "see $data/headless.log"
    exit 0
fi

echo "opening the demo. Nothing outside $data is touched."
exec "$factorio" --config "$data/config.ini" --mod-directory "$data/mods" --load-game "$save"
