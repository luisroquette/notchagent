#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

matrix_file="${1:-}"
[[ -f "$matrix_file" ]] || {
    echo "Usage: $0 /path/to/private-matrix.json" >&2
    exit 2
}

jq -e '
  . as $matrix |
  .schemaVersion == 3 and
  (keys | sort) == ["entries","matrixAlias","schemaVersion"] and
  (.matrixAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
  (.entries | length) >= 6 and
  ([.entries[] | "\(.macClass)|\(.connectionClass)"] | unique | length) == (.entries | length) and
  all(.entries[];
    (keys | sort) == (["attempts","connectionAlias","connectionClass","firmwareVersion",
      "macClass","macOSMajor","maximumConnectionSeconds","maximumInvalidFrameCount",
      "maximumTouchReadErrorCount","minimumFramesPerSecond","minimumFreeHeapBytes",
      "successes","touchControllerPresentEveryAttempt","unitAlias","firmwareImageSHA256",
      "firmwareSourceSHA256","sourceReport","sourceReportSHA256"] | sort) and
    (.macClass | test("^[a-z0-9][a-z0-9-]{2,47}$")) and
    (.macOSMajor | type) == "number" and .macOSMajor == (.macOSMajor | floor) and .macOSMajor >= 14 and
    (.unitAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
    (.connectionClass == "direct" or .connectionClass == "dock" or .connectionClass == "hub") and
    (.connectionAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
    (if .connectionClass == "direct" then .connectionAlias == "DIRECT" else .connectionAlias != "DIRECT" end) and
    .firmwareVersion == "0.6.16" and
    (.firmwareImageSHA256 | test("^[0-9a-f]{64}$")) and
    (.firmwareSourceSHA256 | test("^[0-9a-f]{64}$")) and
    (.sourceReport | type == "string" and length > 0) and
    (.sourceReportSHA256 | test("^[0-9a-f]{64}$")) and
    (.attempts | type) == "number" and .attempts == (.attempts | floor) and .attempts >= 10 and
    (.successes | type) == "number" and .successes == .attempts and
    (.maximumConnectionSeconds | type) == "number" and
      .maximumConnectionSeconds >= 0 and .maximumConnectionSeconds <= 15 and
    (.minimumFramesPerSecond | type) == "number" and .minimumFramesPerSecond >= 7 and
    (.minimumFreeHeapBytes | type) == "number" and .minimumFreeHeapBytes >= 122880 and
    .maximumInvalidFrameCount == 0 and .maximumTouchReadErrorCount == 0 and
    .touchControllerPresentEveryAttempt == true
  ) and
  ([.entries[].sourceReportSHA256] | unique | length) == (.entries | length) and
  ([.entries[].firmwareVersion] | unique) == ["0.6.16"] and
  ([.entries[].macClass] | unique | length) >= 2 and
  all(([$matrix.entries[].macClass] | unique[]);
    . as $mac |
    ([$matrix.entries[] | select(.macClass == $mac) | .connectionClass] | unique | sort) == ["direct","dock","hub"]
  ) and
  ([.entries[] | select(.connectionClass == "dock") | .connectionAlias] | unique | length) >= 1 and
  ([.entries[] | select(.connectionClass == "hub") | .connectionAlias] | unique | length) >= 1
' "$matrix_file" >/dev/null || {
    echo "NOT READY: dock/hub/Mac matrix does not satisfy the Beta 1 reliability contract." >&2
    exit 1
}

while IFS= read -r entry; do
    source_report=$(jq -r '.sourceReport' <<<"$entry")
    [[ -f "$source_report" && ! -L "$source_report" ]] || {
        echo "NOT READY: matrix raw reconnect report is missing or is a symbolic link: $source_report" >&2
        exit 1
    }
    recorded_sha=$(jq -r '.sourceReportSHA256' <<<"$entry")
    actual_sha=$(shasum -a 256 "$source_report" | awk '{print $1}')
    [[ "$actual_sha" == "$recorded_sha" ]] || {
        echo "NOT READY: matrix raw reconnect report SHA-256 does not match: $source_report" >&2
        exit 1
    }

    mac_class=$(jq -r '.macClass' <<<"$entry")
    macos_major=$(jq -r '.macOSMajor' <<<"$entry")
    unit_alias=$(jq -r '.unitAlias' <<<"$entry")
    connection_class=$(jq -r '.connectionClass' <<<"$entry")
    connection_alias=$(jq -r '.connectionAlias' <<<"$entry")
    recomputed=$(NOTCHAGENT_DESK_MATRIX_MACOS_MAJOR="$macos_major" \
      Scripts/notchagent-desk-matrix-entry.sh "$source_report" "$mac_class" "$unit_alias" \
      "$connection_class" "$connection_alias") || {
        echo "NOT READY: matrix raw reconnect report cannot be recomputed: $source_report" >&2
        exit 1
    }
    jq -e --argjson recomputed "$recomputed" '. == $recomputed' <<<"$entry" >/dev/null || {
        echo "NOT READY: matrix entry differs from its recomputed raw evidence: $source_report" >&2
        exit 1
    }
done < <(jq -c '.entries[]' "$matrix_file")

jq -e --slurpfile package firmware/notchagent_desk/release/manifest.json '
  all(.entries[];
    .firmwareVersion == $package[0].firmwareVersion and
    .firmwareImageSHA256 == $package[0].imageSHA256 and
    .firmwareSourceSHA256 == $package[0].sourceSHA256)
' "$matrix_file" >/dev/null || {
    echo "NOT READY: matrix entries do not match the current factory firmware package." >&2
    exit 1
}

echo "PASS: matrix covers direct USB, dock, and hub across at least two Mac classes with healthy repeated connections."
