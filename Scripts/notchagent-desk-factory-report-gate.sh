#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

minimum_units="${NOTCHAGENT_DESK_FACTORY_MIN_UNITS:-1}"
expected_lot_alias="${NOTCHAGENT_DESK_LOT_ALIAS:-}"
[[ "$minimum_units" =~ '^[1-9][0-9]*$' ]] || {
    echo "FAIL: NOTCHAGENT_DESK_FACTORY_MIN_UNITS must be a positive integer." >&2
    exit 2
}
[[ "$expected_lot_alias" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' ]] || {
    echo "FAIL: NOTCHAGENT_DESK_LOT_ALIAS must identify the approved procurement lot." >&2
    exit 2
}
(( $# >= minimum_units )) || {
    echo "Usage: NOTCHAGENT_DESK_FACTORY_MIN_UNITS=N $0 qc-report.json [...]" >&2
    exit 2
}

reports=("$@")
release="firmware/notchagent_desk/release"
firmware/notchagent_desk/verify-release.sh "$release" >/dev/null
jq -e '.firmwareVersion == "0.6.16"' "$release/manifest.json" >/dev/null || {
    echo "NOT READY: factory package is not the Beta 1 firmware 0.6.16." >&2
    exit 1
}
expected_manifest_sha=$(shasum -a 256 "$release/manifest.json" | awk '{print $1}')
all_visual_evidence_shas=()
all_visual_artifact_shas=()
for report in "${reports[@]}"; do
    [[ -f "$report" && ! -L "$report" ]] || { echo "NOT READY: factory report is missing or linked: $report" >&2; exit 1; }
    jq -e --arg expectedManifestSHA256 "$expected_manifest_sha" \
      --arg expectedLotAlias "$expected_lot_alias" '
      .schemaVersion == 7 and
      (keys | sort) == (["schemaVersion","lotAlias","unitAlias","startedAt","completedAt","firmwareVersion",
        "flashVerified","usbReenumerated","telemetryHealthy","checks","packageManifestSHA256",
        "telemetryReport","telemetrySHA256","telemetry","visualEvidenceFile",
        "visualEvidenceSHA256","result"] | sort) and
      (.unitAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
      .lotAlias == $expectedLotAlias and
      .firmwareVersion == "0.6.16" and
      .flashVerified == true and .usbReenumerated == true and .telemetryHealthy == true and
      .packageManifestSHA256 == $expectedManifestSHA256 and
      (.checks | keys | sort) == ["display","runner","swipe","touch"] and
      all(.checks[]; . == "pass") and
      (.telemetrySHA256 | test("^[0-9a-f]{64}$")) and
      (.visualEvidenceFile | type == "string" and test("\\S")) and
      (.visualEvidenceSHA256 | test("^[0-9a-f]{64}$")) and
      (.telemetry | keys | sort) == (["sampleCount","firmwareVersion","minimumFramesPerSecond","minimumFreeHeapBytes",
        "maximumInvalidFrameCount","maximumTouchReadErrorCount","touchControllerPresentEverySample",
        "resetReasons"] | sort) and
      .telemetry.sampleCount >= 2 and .telemetry.firmwareVersion == "0.6.16" and
      .telemetry.minimumFramesPerSecond >= 7 and .telemetry.minimumFreeHeapBytes >= 122880 and
      .telemetry.maximumInvalidFrameCount == 0 and .telemetry.maximumTouchReadErrorCount == 0 and
      .telemetry.touchControllerPresentEverySample == true and
      (.telemetry.resetReasons | index("usb")) != null and
      (.startedAt | fromdateiso8601) <= (.completedAt | fromdateiso8601) and
      .result == "accepted"
    ' "$report" >/dev/null || {
        echo "NOT READY: factory report does not prove an accepted unit: $report" >&2
        exit 1
    }
    telemetry_report=$(jq -r '.telemetryReport' "$report")
    [[ -f "$telemetry_report" && ! -L "$telemetry_report" &&
       "$(shasum -a 256 "$telemetry_report" | awk '{print $1}')" ==
       "$(jq -r '.telemetrySHA256' "$report")" ]] || {
        echo "NOT READY: factory telemetry source is missing, linked, or changed: $report" >&2
        exit 1
    }
    recomputed_telemetry=$(Scripts/notchagent-desk-telemetry-evidence.sh "$telemetry_report") || {
        echo "NOT READY: factory telemetry source is unhealthy: $report" >&2
        exit 1
    }
    jq -e --argjson recomputed "$recomputed_telemetry" '.telemetry == $recomputed' \
      "$report" >/dev/null || {
        echo "NOT READY: factory telemetry summary does not match its source: $report" >&2
        exit 1
    }
    visual_evidence=$(jq -r '.visualEvidenceFile' "$report")
    visual_evidence_sha=$(jq -r '.visualEvidenceSHA256' "$report")
    [[ -f "$visual_evidence" && ! -L "$visual_evidence" &&
       "$(shasum -a 256 "$visual_evidence" | awk '{print $1}')" == "$visual_evidence_sha" ]] || {
        echo "NOT READY: factory visual evidence is missing, linked, or changed: $report" >&2
        exit 1
    }
    Scripts/notchagent-desk-factory-visual-gate.sh "$visual_evidence" \
      "$expected_lot_alias" "$(jq -r '.unitAlias' "$report")" >/dev/null || exit 1
    visual_captured_epoch=$(jq -r '.capturedAt | fromdateiso8601' "$visual_evidence")
    report_started_epoch=$(jq -r '.startedAt | fromdateiso8601' "$report")
    report_completed_epoch=$(jq -r '.completedAt | fromdateiso8601' "$report")
    (( visual_captured_epoch >= report_started_epoch - 3600 &&
       visual_captured_epoch <= report_completed_epoch )) || {
        echo "NOT READY: factory visual evidence is outside the unit QC window: $report" >&2
        exit 1
    }
    all_visual_evidence_shas+=("$visual_evidence_sha")
    all_visual_artifact_shas+=("${(@f)$(jq -r '.artifacts[].sha256' "$visual_evidence")}")
done

unique_lot_alias_count=$(jq -s '[.[].lotAlias] | unique | length' "${reports[@]}")
(( unique_lot_alias_count == 1 )) || {
    echo "NOT READY: factory reports mix procurement lots." >&2
    exit 1
}

unique_unit_alias_count=$(jq -s '[.[].unitAlias] | unique | length' "${reports[@]}")
(( unique_unit_alias_count == ${#reports[@]} )) || {
    echo "NOT READY: factory reports repeat a unit alias." >&2
    exit 1
}
unique_telemetry_count=$(jq -s '[.[].telemetrySHA256] | unique | length' "${reports[@]}")
(( unique_telemetry_count == ${#reports[@]} )) || {
    echo "NOT READY: factory reports reuse telemetry evidence." >&2
    exit 1
}
unique_visual_evidence_count=$(printf '%s\n' "${all_visual_evidence_shas[@]}" | sort -u | wc -l | tr -d '[:space:]')
(( unique_visual_evidence_count == ${#reports[@]} )) || {
    echo "NOT READY: factory reports reuse visual evidence." >&2
    exit 1
}
unique_visual_artifact_count=$(printf '%s\n' "${all_visual_artifact_shas[@]}" | sort -u | wc -l | tr -d '[:space:]')
(( unique_visual_artifact_count == ${#all_visual_artifact_shas} )) || {
    echo "NOT READY: factory units reuse display, touch, swipe, or runner artifacts." >&2
    exit 1
}

echo "PASS: ${#reports[@]} unique factory unit report(s) prove flash, USB, telemetry, display, touch, swipe, and runner acceptance."
