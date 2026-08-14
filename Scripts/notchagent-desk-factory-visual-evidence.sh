#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

output="${1:-}"
lot_alias="${2:-}"
unit_alias="${3:-}"
display_file="${4:-}"
touch_file="${5:-}"
swipe_file="${6:-}"
runner_file="${7:-}"
[[ "$output" == /* && ! -e "$output" && -d "${output:h}" &&
   "$lot_alias" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' &&
   "$unit_alias" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' ]] || {
    echo "Usage: $0 /absolute/new-evidence.json LOT UNIT display.png touch.png swipe.png runner.png" >&2
    exit 2
}
for artifact in "$display_file" "$touch_file" "$swipe_file" "$runner_file"; do
    [[ -s "$artifact" && ! -L "$artifact" ]] || {
        echo "INVALID: every visual artifact must be a nonempty regular file: $artifact" >&2
        exit 2
    }
done

tmp=$(mktemp "${output:h}/.factory-visual.XXXXXX")
cleanup() { [[ ! -f "$tmp" ]] || rm -- "$tmp"; }
trap cleanup EXIT
jq -n \
  --arg lotAlias "$lot_alias" --arg unitAlias "$unit_alias" \
  --arg capturedAt "$(date -u +%FT%TZ)" \
  --arg displayFile "$display_file" --arg displaySHA "$(shasum -a 256 "$display_file" | awk '{print $1}')" \
  --arg touchFile "$touch_file" --arg touchSHA "$(shasum -a 256 "$touch_file" | awk '{print $1}')" \
  --arg swipeFile "$swipe_file" --arg swipeSHA "$(shasum -a 256 "$swipe_file" | awk '{print $1}')" \
  --arg runnerFile "$runner_file" --arg runnerSHA "$(shasum -a 256 "$runner_file" | awk '{print $1}')" '
  {schemaVersion:1,lotAlias:$lotAlias,unitAlias:$unitAlias,capturedAt:$capturedAt,
   artifacts:{display:{file:$displayFile,sha256:$displaySHA},touch:{file:$touchFile,sha256:$touchSHA},
    swipe:{file:$swipeFile,sha256:$swipeSHA},runner:{file:$runnerFile,sha256:$runnerSHA}},
   result:"pass"}
' > "$tmp"
Scripts/notchagent-desk-factory-visual-gate.sh "$tmp" "$lot_alias" "$unit_alias" >/dev/null
mv -- "$tmp" "$output"
echo "PASS: private factory visual evidence created at $output"
