#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

output="${1:-}"
lot_alias="${2:-}"
unit_alias="${3:-}"
[[ "$output" == /* && ! -e "$output" && -d "${output:h}" &&
   "$lot_alias" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' &&
   "$unit_alias" =~ '^DESK-B1-[0-9]{3,6}$' ]] || {
    echo "Usage: $0 /absolute/new-label.svg LOT-ALIAS DESK-B1-NNN" >&2
    exit 2
}

release="docs/NOTCHAGENT_DESK_RELEASE.json"
firmware=$(jq -er '.firmwareVersion | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$release")
protocol=$(jq -er '.protocolVersion | select(test("^[0-9]+\\.[0-9]+$"))' "$release")
tmp=$(mktemp "${output:h}/.unit-label.XXXXXX")
cleanup() { [[ ! -f "$tmp" ]] || rm -- "$tmp"; }
trap cleanup EXIT

print -r -- "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"50mm\" height=\"30mm\" viewBox=\"0 0 500 300\">
  <rect width=\"500\" height=\"300\" rx=\"22\" fill=\"#0B0D10\"/>
  <rect x=\"12\" y=\"12\" width=\"476\" height=\"276\" rx=\"16\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"3\"/>
  <text x=\"32\" y=\"66\" fill=\"#FFFFFF\" font-family=\"-apple-system,Helvetica,Arial,sans-serif\" font-size=\"28\" font-weight=\"700\">NotchAgent Desk</text>
  <text x=\"32\" y=\"145\" fill=\"#FFFFFF\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"48\" font-weight=\"700\">$unit_alias</text>
  <text x=\"32\" y=\"205\" fill=\"#B8C0CC\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"22\">LOT $lot_alias</text>
  <text x=\"32\" y=\"252\" fill=\"#B8C0CC\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"20\">FW $firmware  ·  PROTOCOL $protocol</text>
</svg>" > "$tmp"

[[ -s "$tmp" ]] || { echo "FAIL: empty label." >&2; exit 1; }
if rg -qi 'serial|mac address|customer|credential|usbmodem' "$tmp"; then
    echo "FAIL: unit label contains a forbidden identifier field." >&2
    exit 1
fi
mv -- "$tmp" "$output"
echo "PASS: printable non-identifying unit label created at $output"
