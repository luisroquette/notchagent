#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

evidence="${1:-}"
participant_alias="${2:-}"
[[ -f "$evidence" && ! -L "$evidence" && "$participant_alias" =~ '^P[0-9]{2}$' ]] || {
    echo "Usage: $0 consent-evidence.json P01" >&2
    exit 2
}
jq -e --arg participantAlias "$participant_alias" '
  .schemaVersion == 1 and
  (keys | sort) == (["schemaVersion","participantAlias","consentedAt","documentFile",
    "documentSHA256","scopes","result"] | sort) and
  .participantAlias == $participantAlias and
  (.consentedAt | fromdateiso8601) <= now and
  (.documentFile | type == "string" and test("\\S")) and
  (.documentSHA256 | test("^[0-9a-f]{64}$")) and
  .scopes == {localDiagnostics:true,usabilityStudy:true} and
  .result == "accepted"
' "$evidence" >/dev/null || {
    echo "NOT READY: $participant_alias consent record is incomplete or mismatched." >&2
    exit 1
}
document=$(jq -r '.documentFile' "$evidence")
expected_sha=$(jq -r '.documentSHA256' "$evidence")
[[ -s "$document" && ! -L "$document" &&
   "$(shasum -a 256 "$document" | awk '{print $1}')" == "$expected_sha" ]] || {
    echo "NOT READY: $participant_alias consent document is missing, empty, linked, or changed." >&2
    exit 1
}
mime=$(file -b --mime-type "$document")
[[ "$mime" == application/pdf || "$mime" == image/png ||
   "$mime" == image/jpeg || "$mime" == image/heic ]] || {
    echo "NOT READY: $participant_alias consent document must be PDF, PNG, JPEG, or HEIC." >&2
    exit 1
}
echo "PASS: $participant_alias consent document is present and hash-verified."
