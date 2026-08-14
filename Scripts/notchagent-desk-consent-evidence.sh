#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

output="${1:-}"
participant_alias="${2:-}"
document="${3:-}"
[[ "$output" == /* && ! -e "$output" && -d "${output:h}" &&
   "$participant_alias" =~ '^P[0-9]{2}$' && -s "$document" && ! -L "$document" ]] || {
    echo "Usage: $0 /absolute/new-consent.json P01 /absolute/private/consent.pdf" >&2
    exit 2
}
tmp=$(mktemp "${output:h}/.consent-evidence.XXXXXX")
cleanup() { [[ ! -f "$tmp" ]] || rm -- "$tmp"; }
trap cleanup EXIT
jq -n --arg participantAlias "$participant_alias" \
  --arg consentedAt "$(date -u +%FT%TZ)" --arg documentFile "$document" \
  --arg documentSHA256 "$(shasum -a 256 "$document" | awk '{print $1}')" '
  {schemaVersion:1,participantAlias:$participantAlias,consentedAt:$consentedAt,
   documentFile:$documentFile,documentSHA256:$documentSHA256,
   scopes:{localDiagnostics:true,usabilityStudy:true},result:"accepted"}
' > "$tmp"
Scripts/notchagent-desk-consent-gate.sh "$tmp" "$participant_alias" >/dev/null
mv -- "$tmp" "$output"
echo "PASS: private consent evidence created at $output"
