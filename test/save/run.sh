#!/usr/bin/env bash
# Save tier: does the mod still know its factory after the game has been saved and loaded?
#
#   test/save/run.sh
#
# The integration suite cannot answer this. It runs inside one session, and what is being
# tested is the boundary between two: the mod keeps entity references in storage, and a
# reference is a thing the engine has to write into a save and hand back on the way in.
#
# So this runs the game twice. The first run builds a factory, lets the mod pick it up and
# start feeding piles, writes down what it saw and saves. The second run loads that save and
# checks the mod still knows the same inserters, that the references are still good, and
# that the piles go on growing.
#
# IGS_SAVE_FACTORIO   the game binary; a headless build is enough and is the default
# IGS_SAVE_DATA       the throwaway data directory the run happens in
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

factorio="${IGS_SAVE_FACTORIO:-$HOME/.local/share/factorio-versions/2.1.17/bin/x64/factorio}"
data="${IGS_SAVE_DATA:-$HOME/.cache/igs-save-test}"

[[ -x "$factorio" ]] || { echo "no factorio binary at $factorio" >&2; exit 2; }

rm -rf "$data"
mkdir -p "$data/mods" "$data/saves" "$data/script-output"

# A config of its own, so the run writes its save, its script output and its player data
# here rather than into the directory the binary happens to live in. Without this a headless
# build puts all three next to itself, and the harness looks in the wrong place for both.
install_root="$(cd "$(dirname "$factorio")/../.." && pwd)"
cat > "$data/config.ini" <<INI
[path]
read-data=$install_root/data
write-data=$data
INI

# The mod under test and the harness beside it, symlinked rather than copied so a run always
# exercises the working tree.
ln -sfn "$root" "$data/mods/inserter-ground-stack"
ln -sfn "$root/test/save/igs-save" "$data/mods/igs-save"
# The expansion mods ship inside the game's data directory and default to on, so a vanilla
# run has to switch them off by name rather than by leaving them out.
cat > "$data/mods/mod-list.json" <<'JSON'
{"mods":[
  {"name":"base","enabled":true},
  {"name":"elevated-rails","enabled":false},
  {"name":"quality","enabled":false},
  {"name":"recycler","enabled":false},
  {"name":"space-age","enabled":false},
  {"name":"inserter-ground-stack","enabled":true},
  {"name":"igs-save","enabled":true}
]}
JSON

# A headless server with nobody connected pauses by default and never advances a tick, and
# the stock example settings ask to be listed publicly, which fails without a login token.
cat > "$data/server-settings.json" <<'JSON'
{ "name": "igs-save-test", "description": "", "visibility": { "public": false, "lan": false },
  "require_user_verification": false, "auto_pause": false }
JSON

save="$data/saves/igs-save-roundtrip.zip"
result="$data/script-output/igs-save-result.txt"

run() {
    # stdin has to stay open or the server quits the moment it sees EOF
    timeout "$2" "$factorio" --start-server "$save" \
        --config "$data/config.ini" \
        --mod-directory "$data/mods" \
        --server-settings "$data/server-settings.json" \
        < <(sleep "$3") > "$data/run-$1.log" 2>&1 || true
}

echo "building the factory and saving it..."
"$factorio" --create "$save" --config "$data/config.ini" \
    --mod-directory "$data/mods" > "$data/create.log" 2>&1
run one 45 16

[[ -f "$result" ]] || { echo "the first run wrote no result file; see $data/run-one.log" >&2; exit 1; }
grep -q "^SAVED" "$result" || { echo "the first run never saved; see $result" >&2; cat "$result" >&2; exit 1; }

echo "loading it again and checking..."
run two 45 16

echo
cat "$result"
echo

if grep -q "^FAIL" "$result"; then
    echo "save round trip FAILED" >&2
    exit 1
fi
passes=$(grep -c "^PASS" "$result" || true)
[[ "$passes" -ge 3 ]] || {
    echo "expected at least three checks to pass, got $passes; the second run may not have got far" >&2
    exit 1
}
grep -q "^DONE" "$result" || { echo "the second run did not finish" >&2; exit 1; }
echo "save round trip passed ($passes checks)"
