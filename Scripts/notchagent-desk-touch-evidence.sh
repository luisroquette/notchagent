#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

report="${1:-}"
tap="${2:-pending}"
swipe_left="${3:-pending}"
swipe_right="${4:-pending}"
runner_jump="${5:-pending}"
output="${6:-docs/evidence/notchagent-desk-beta1-touch-$(date -u +%Y%m%dT%H%M%SZ).json}"
[[ -f "$report" ]] || {
    echo "Usage: $0 soak.jsonl tap-result swipe-left-result swipe-right-result runner-jump-result [output.json]" >&2
    exit 2
}
for result in "$tap" "$swipe_left" "$swipe_right" "$runner_jump"; do
    [[ "$result" == pass || "$result" == fail || "$result" == pending ]] || {
        echo "FAIL: physical results accept only pass, fail, or pending." >&2
        exit 2
    }
done
[[ "$output" == *.json && ! -e "$output" ]] || {
    echo "FAIL: output must be a new JSON path; prior evidence is preserved." >&2
    exit 2
}
source_snapshot="${output:r}-source.jsonl"
[[ ! -e "$source_snapshot" ]] || {
    echo "FAIL: touch source snapshot already exists; prior evidence is preserved." >&2
    exit 2
}
output_dir="${output:h}"
mkdir -p "$output_dir"
source_tmp=$(mktemp "${source_snapshot:h}/.touch-source.XXXXXX")
tmp=""
cleanup() {
    [[ ! -f "$source_tmp" ]] || rm -- "$source_tmp"
    [[ -z "$tmp" || ! -f "$tmp" ]] || rm -- "$tmp"
}
trap cleanup EXIT
jq -c . "$report" > "$source_tmp"

tmp=$(mktemp "$output_dir/.touch-evidence.XXXXXX")
Scripts/notchagent-desk-touch-summary.sh "$source_tmp" "$tap" "$swipe_left" \
  "$swipe_right" "$runner_jump" "$source_snapshot" > "$tmp"
final_status=$(jq -r '.status' "$tmp")
mv -- "$source_tmp" "$source_snapshot"
mv -- "$tmp" "$output"
echo "${final_status:u}: touch evidence captured at $output"
[[ "$final_status" == pass ]] || exit 1
