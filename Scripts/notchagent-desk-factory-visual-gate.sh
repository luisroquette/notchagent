#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

evidence="${1:-}"
expected_lot="${2:-}"
expected_unit="${3:-}"
[[ -f "$evidence" && ! -L "$evidence" &&
   "$expected_lot" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' &&
   "$expected_unit" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' ]] || {
    echo "Usage: $0 visual-evidence.json LOT-ALIAS UNIT-ALIAS" >&2
    exit 2
}

jq -e --arg lotAlias "$expected_lot" --arg unitAlias "$expected_unit" '
  .schemaVersion == 1 and
  (keys | sort) == (["schemaVersion","lotAlias","unitAlias","capturedAt","artifacts","result"] | sort) and
  .lotAlias == $lotAlias and .unitAlias == $unitAlias and
  (.capturedAt | fromdateiso8601) <= now and
  (.artifacts | keys | sort) == ["display","runner","swipe","touch"] and
  all(.artifacts[];
    (keys | sort) == ["file","sha256"] and
    (.file | type == "string" and test("\\S")) and
    (.sha256 | test("^[0-9a-f]{64}$"))) and
  ([.artifacts[].file] | unique | length) == 4 and
  ([.artifacts[].sha256] | unique | length) == 4 and
  .result == "pass"
' "$evidence" >/dev/null || {
    echo "NOT READY: factory visual evidence is incomplete or mismatched." >&2
    exit 1
}

while IFS=$'\t' read -r check artifact expected_sha; do
    [[ -s "$artifact" && ! -L "$artifact" ]] || {
        echo "NOT READY: $check artifact is missing, empty, or linked: $artifact" >&2
        exit 1
    }
    mime=$(file -b --mime-type "$artifact")
    [[ "$mime" == image/png || "$mime" == image/jpeg || "$mime" == image/heic ]] || {
        echo "NOT READY: $check artifact must be PNG, JPEG, or HEIC: $artifact" >&2
        exit 1
    }
    [[ "$(shasum -a 256 "$artifact" | awk '{print $1}')" == "$expected_sha" ]] || {
        echo "NOT READY: $check artifact hash does not match: $artifact" >&2
        exit 1
    }
done < <(jq -r '.artifacts | to_entries[] | [.key,.value.file,.value.sha256] | @tsv' "$evidence")

echo "PASS: factory display, touch, swipe, and runner artifacts are present and hash-verified."
