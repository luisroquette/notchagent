#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

evidence="${1:-}"
[[ -f "$evidence" && ! -L "$evidence" ]] || {
    echo "Usage: $0 ai-visual-review.json" >&2
    exit 2
}

jq -e '
  .schemaVersion == 1 and .gate == "ai-visual-review" and .result == "pass" and
  .appVersion == "3.1.1" and .buildNumber == "4" and
  .source == "live-signed-macos-app" and .reviewer == "codex-vision" and
  .productOwnerWaiver == true and .generatedImagery == false and
  (.artifacts | length) == 2 and
  ([.artifacts[].role] | sort) == ["alert-expanded", "compact-dashboard"] and
  all(.artifacts[];
    (.file | type == "string" and startswith("docs/evidence/ai-visual-review-")) and
    (.sha256 | test("^[0-9a-f]{64}$")) and .width == 1440 and .height == 920) and
  .observations == {hierarchy:"pass",contrast:"pass",legibility:"pass",animation:"pass"} and
  .limitation == "Does not validate physical touch latency or hardware interaction."
' "$evidence" >/dev/null || {
    echo "INVALID: AI visual review evidence is incomplete or misleading." >&2
    exit 1
}

artifact_shas=()
for row in "${(@f)$(jq -r '.artifacts[] | [.file,.sha256,.width,.height] | @tsv' "$evidence")}"; do
    IFS=$'\t' read -r artifact expected_sha expected_width expected_height <<<"$row"
    [[ -f "$artifact" && ! -L "$artifact" ]] || {
        echo "INVALID: AI review artifact is missing or linked." >&2
        exit 1
    }
    actual_sha=$(shasum -a 256 "$artifact" | awk '{print $1}')
    actual_width=$(sips -g pixelWidth "$artifact" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    actual_height=$(sips -g pixelHeight "$artifact" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    [[ "$actual_sha" == "$expected_sha" && "$actual_width" == "$expected_width" &&
       "$actual_height" == "$expected_height" ]] || {
        echo "INVALID: AI review artifact changed after approval." >&2
        exit 1
    }
    artifact_shas+=("$actual_sha")
done

[[ "${artifact_shas[1]}" != "${artifact_shas[2]}" ]] || {
    echo "INVALID: AI review requires two distinct live render states." >&2
    exit 1
}

echo "PASS: live macOS AI visual review is complete and explicitly excludes physical-touch claims."
