#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

status_file="${NOTCHAGENT_DESK_BETA1_STATUS_FILE:-docs/evidence/notchagent-desk-beta1-status.json}"
release_contract="docs/NOTCHAGENT_DESK_RELEASE.json"
firmware_package_manifest="firmware/notchagent_desk/release/manifest.json"
expected_gates='["abrupt-power-recovery","automatic-discovery","bom-enclosure-cable-freeze","developer-id-notarization","dock-hub-mac-matrix","factory-qc-flow","firmware-protocol-visible","five-user-seven-day-pilot","hardware-telemetry","local-ambient-intelligence","local-signed-recovery","onboarding-qr","physical-reconnect-100","physical-touch-latency","sanitized-diagnostics","soak-24-hours"]'
for trusted_contract in "$status_file" "$release_contract" "$firmware_package_manifest"; do
    [[ -f "$trusted_contract" && ! -L "$trusted_contract" ]] || {
        echo "INVALID: release contract is missing or is a symbolic link: $trusted_contract" >&2
        exit 1
    }
done
jq -e --argjson expected "$expected_gates" '
  .schemaVersion == 1 and
  (keys | sort) == ["gates","product","schemaVersion","updatedAt"] and
  .product == "NotchAgent Desk Beta 1" and
  (.updatedAt | fromdateiso8601 | type) == "number" and
  (.gates | type) == "array" and
  ([.gates[].id] | sort) == $expected and
  all(.gates[];
    (keys | sort) == ["evidence","id","status"] and
    (.status == "pass" or .status == "pending" or .status == "fail" or .status == "waived") and
    (.evidence | type) == "string" and (.evidence | length) > 0)
' "$status_file" >/dev/null || {
    echo "INVALID: Beta 1 status schema or gate inventory is incomplete." >&2
    exit 1
}
jq -e '
  .schemaVersion == 1 and .product == "NotchAgent Desk Beta 1" and
  (keys | sort) == ["appVersion","buildNumber","channel","firmwareVersion","product","protocolVersion","schemaVersion"] and
  .channel == "beta" and .appVersion == "3.1.2" and .buildNumber == "5" and
  .firmwareVersion == "0.6.16" and .protocolVersion == "1.1"
' "$release_contract" >/dev/null || {
    echo "INVALID: Beta 1 release version contract is incomplete." >&2
    exit 1
}

gate_status() {
    jq -r --arg id "$1" '.gates[] | select(.id == $id) | .status' "$status_file"
}

gate_evidence() {
    jq -r --arg id "$1" '.gates[] | select(.id == $id) | .evidence' "$status_file"
}

require_evidence_file() {
    local id="$1"
    local evidence
    evidence=$(gate_evidence "$id")
    [[ -f "$evidence" && ! -L "$evidence" ]] || {
        echo "INVALID: $id evidence is missing or is a symbolic link: $evidence" >&2
        exit 1
    }
    print -r -- "$evidence"
}

validate_smoke_source() {
    local evidence="$1"
    local source
    source=$(jq -r '.sourceReport' "$evidence")
    [[ -f "$source" && ! -L "$source" &&
       "$(shasum -a 256 "$source" | awk '{print $1}')" ==
       "$(jq -r '.reportSHA256' "$evidence")" ]] || return 1
    jq -s -e --slurpfile evidence "$evidence" '
      [.[] | select(.telemetry != null)] as $samples |
      ($samples[0].elapsedMilliseconds // -1) as $first |
      ($samples[-1].elapsedMilliseconds // -1) as $last |
      ([range(1; $samples|length) as $i |
        $samples[$i].elapsedMilliseconds - $samples[$i - 1].elapsedMilliseconds] | max // 0) as $gap |
      ($samples | length) >= 10 and $first >= 0 and ($last - $first) >= 45000 and $gap <= 10000 and
      all(.[] | select(.elapsedMilliseconds >= $first and .elapsedMilliseconds <= $last);
        .phase == "connected") and
      all($samples[];
        .firmwareVersion == "0.6.16" and .protocolMajor == 1 and .protocolMinor == 1 and
        .telemetry.firmwareVersion == "0.6.16" and .telemetry.framesPerSecond >= 7 and
        .telemetry.minimumFreeHeapBytes >= 122880 and .telemetry.invalidFrameCount == 0 and
        (.telemetry.touchReadErrorCount // 0) == 0 and .telemetry.touchControllerPresent == true and
        (.reliabilityFailures | length) == 0) and
      $evidence[0].capturedAt == $samples[-1].capturedAt and
      $evidence[0].durationSeconds == ((($last - $first) / 1000) | floor) and
      $evidence[0].firstConnectionMilliseconds == $first and
      $evidence[0].maximumSampleGapMilliseconds == $gap and
      $evidence[0].minimumFramesPerSecond == ($samples | map(.telemetry.framesPerSecond) | min) and
      $evidence[0].minimumFreeHeapBytes == ($samples | map(.telemetry.minimumFreeHeapBytes) | min) and
      $evidence[0].maximumInvalidFrameCount == ($samples | map(.telemetry.invalidFrameCount) | max) and
      $evidence[0].maximumTouchReadErrorCount == ($samples | map(.telemetry.touchReadErrorCount // 0) | max) and
      $evidence[0].touchControllerPresent == all($samples[]; .telemetry.touchControllerPresent == true) and
      $evidence[0].touchCount == ($samples | map(.telemetry.touchCount // 0) | max)
    ' "$source" >/dev/null
}

if [[ "$(gate_status firmware-protocol-visible)" == "pass" ]]; then
    identity_evidence=$(require_evidence_file firmware-protocol-visible)
    jq -e --slurpfile package "$firmware_package_manifest" '
      .schemaVersion == 2 and .gate == "firmware-protocol-visible" and .result == "pass" and
      .firmwareVersion == "0.6.16" and .protocolVersion == "1.1" and
      .firmwareVersion == $package[0].firmwareVersion and
      .firmwareImageSHA256 == $package[0].imageSHA256 and
      .firmwareSourceSHA256 == $package[0].sourceSHA256 and
      .telemetryFirmwareVersion == .firmwareVersion and .telemetryPresent == true and
      (.capturedAt | fromdateiso8601 | type) == "number" and
      (.sourceReportSHA256 | test("^[0-9a-f]{64}$"))
    ' "$identity_evidence" >/dev/null || {
        echo "INVALID: firmware-protocol-visible evidence does not satisfy the gate." >&2
        exit 1
    }
    identity_source=$(jq -r '.sourceReport' "$identity_evidence")
    [[ -f "$identity_source" && ! -L "$identity_source" &&
       "$(shasum -a 256 "$identity_source" | awk '{print $1}')" ==
       "$(jq -r '.sourceReportSHA256' "$identity_evidence")" ]] || {
        echo "INVALID: firmware identity source report is missing or has changed." >&2
       exit 1
    }
    jq -s -e --slurpfile evidence "$identity_evidence" '
      [.[] | select(.telemetry != null)] as $samples |
      ($samples | length) > 0 and
      $evidence[0].capturedAt == $samples[-1].capturedAt and
      $evidence[0].telemetryFirmwareVersion == $samples[-1].telemetry.firmwareVersion and
      $samples[-1].firmwareVersion == $evidence[0].firmwareVersion and
      (($samples[-1].protocolMajor | tostring) + "." + ($samples[-1].protocolMinor | tostring)) ==
        $evidence[0].protocolVersion
    ' "$identity_source" >/dev/null || {
        echo "INVALID: firmware identity summary does not match its source report." >&2
        exit 1
    }
fi

if [[ "$(gate_status automatic-discovery)" == "pass" ]]; then
    discovery_evidence=$(require_evidence_file automatic-discovery)
    jq -e --slurpfile package "$firmware_package_manifest" '
      .schemaVersion == 2 and .gate == "final-app-physical-smoke" and .result == "pass" and
      .appVersion == "3.1.2" and .buildNumber == "5" and
      .firmwareVersion == "0.6.16" and .protocolVersion == "1.1" and
      .firmwareVersion == $package[0].firmwareVersion and
      .firmwareImageSHA256 == $package[0].imageSHA256 and
      .firmwareSourceSHA256 == $package[0].sourceSHA256 and
      .durationSeconds >= 45 and .connectionContinuity == true and
      .firstConnectionMilliseconds >= 0 and .firstConnectionMilliseconds <= 15000 and
      .maximumSampleGapMilliseconds <= 10000 and
      (.reportSHA256 | test("^[0-9a-f]{64}$"))
    ' "$discovery_evidence" >/dev/null || {
        echo "INVALID: automatic-discovery evidence does not satisfy the gate." >&2
        exit 1
    }
    validate_smoke_source "$discovery_evidence" || {
        echo "INVALID: discovery summary does not match its source report." >&2
        exit 1
    }
fi

if [[ "$(gate_status hardware-telemetry)" == "pass" ]]; then
    telemetry_evidence=$(require_evidence_file hardware-telemetry)
    jq -e --slurpfile package "$firmware_package_manifest" '
      .schemaVersion == 2 and .gate == "final-app-physical-smoke" and .result == "pass" and
      .firmwareVersion == "0.6.16" and .connectionContinuity == true and
      .firmwareVersion == $package[0].firmwareVersion and
      .firmwareImageSHA256 == $package[0].imageSHA256 and
      .firmwareSourceSHA256 == $package[0].sourceSHA256 and
      .minimumFramesPerSecond >= 7 and .minimumFreeHeapBytes >= 122880 and
      .maximumInvalidFrameCount == 0 and .maximumTouchReadErrorCount == 0 and
      .touchControllerPresent == true and
      (.reportSHA256 | test("^[0-9a-f]{64}$"))
    ' "$telemetry_evidence" >/dev/null || {
        echo "INVALID: hardware-telemetry evidence does not satisfy the gate." >&2
        exit 1
    }
    validate_smoke_source "$telemetry_evidence" || {
        echo "INVALID: hardware telemetry summary does not match its source report." >&2
        exit 1
    }
fi

if [[ "$(gate_status local-ambient-intelligence)" == "pass" ]]; then
    ambient_source="Sources/NotchAgent/Features/Desk/NotchAgentDeskAmbientIntelligence.swift"
    [[ -f "$ambient_source" ]] || {
        echo "INVALID: local ambient intelligence source is missing." >&2
        exit 1
    }
    if rg -n 'URLSession|NSURLConnection|Network\.|NWConnection|api\.|https?://' \
        "$ambient_source" >/dev/null; then
        echo "INVALID: ambient intelligence contains a network/API dependency." >&2
        exit 1
    fi
    [[ "$(rg -c '^import ' "$ambient_source")" == 1 ]] &&
      rg -q '^import Foundation$' "$ambient_source" &&
      rg -q 'var reason: String' "$ambient_source" &&
      rg -q 'testAmbientIntelligencePrioritizesRiskThenFocus' \
        Tests/NotchAgentTests/NotchAgentDeskTests.swift || {
        echo "INVALID: local ambient intelligence is not pure, explainable, and regression-tested." >&2
        exit 1
    }
fi

if [[ "$(gate_status sanitized-diagnostics)" == "pass" ]]; then
    diagnostic_source="Sources/NotchAgent/Core/Services/SanitizedDiagnosticExporter.swift"
    [[ -f "$diagnostic_source" ]] &&
      rg -q 'var minimumFreeHeapBytes: UInt32\?' "$diagnostic_source" &&
      rg -q 'var resetReason: String\?' "$diagnostic_source" &&
      rg -q 'var touchReadErrorCount: UInt32\?' "$diagnostic_source" &&
      rg -q 'var maximumTouchLatencyMs: Double\?' "$diagnostic_source" &&
      rg -q 'testSanitizedDiagnosticIncludesDeskIdentityButNotSerialPath' \
        Tests/NotchAgentTests/NotchAgentDeskTests.swift &&
      rg -q 'testSanitizedDiagnosticExcludesCredentialsIdentityAmountsAndErrors' \
        Tests/NotchAgentTests/APIAccountProviderTests.swift || {
        echo "INVALID: sanitized diagnostics lack required hardware fields or privacy regressions." >&2
        exit 1
    }
    if rg -n 'var (serialPath|serialNumber|hardwareUUID|macAddress|hostname|credential|token|password|secret):' \
        "$diagnostic_source" >/dev/null; then
        echo "INVALID: sanitized diagnostic schema exposes a forbidden identifier or secret." >&2
        exit 1
    fi
fi

if [[ "$(gate_status physical-reconnect-100)" == "pass" ]]; then
    reconnect_evidence=$(require_evidence_file physical-reconnect-100)
    jq -e --slurpfile package "$firmware_package_manifest" '
      .schemaVersion == 3 and .gate == "physical-reset-usb-reconnect" and .result == "pass" and
      .firmwareVersion == "0.6.16" and .cycles >= 100 and
      .firmwareVersion == $package[0].firmwareVersion and
      .firmwareImageSHA256 == $package[0].imageSHA256 and
      .firmwareSourceSHA256 == $package[0].sourceSHA256 and
      (.firmwareImageSHA256 | test("^[0-9a-f]{64}$")) and
      (.firmwareSourceSHA256 | test("^[0-9a-f]{64}$")) and
      .maximumReconnectMilliseconds <= 15000 and
      .maximumResetMilliseconds > 0 and .maximumTelemetryMilliseconds > 0 and
      .maximumBootUptimeSeconds <= 30 and .minimumHandshakeCountPerCycle >= 1 and
      .minimumTouchPollAttemptsPerCycle > 0 and .resetReasons == ["usb"] and
      .minimumFramesPerSecond >= 7 and .minimumFreeHeapBytes >= 122880 and
      .maximumInvalidFrameCount == 0 and .maximumTouchReadErrorCount == 0 and
      .touchControllerPresentEveryCycle == true and
      (.sourceReportSHA256 | test("^[0-9a-f]{64}$"))
    ' "$reconnect_evidence" >/dev/null || {
        echo "INVALID: physical-reconnect-100 evidence does not satisfy the gate." >&2
        exit 1
    }
    reconnect_source=$(jq -r '.sourceReport' "$reconnect_evidence")
    [[ -f "$reconnect_source" && ! -L "$reconnect_source" &&
       "$(shasum -a 256 "$reconnect_source" | awk '{print $1}')" ==
       "$(jq -r '.sourceReportSHA256' "$reconnect_evidence")" ]] || {
        echo "INVALID: reconnect source report is missing or has changed." >&2
        exit 1
    }
    recomputed_reconnect=$(Scripts/notchagent-desk-reconnect-evidence.sh "$reconnect_source" 100) || {
        echo "INVALID: reconnect source report no longer satisfies the physical gate." >&2
        exit 1
    }
    jq -e --argjson recomputed "$recomputed_reconnect" '. == $recomputed' \
      "$reconnect_evidence" >/dev/null || {
        echo "INVALID: reconnect summary does not match its source report." >&2
        exit 1
    }
fi

if [[ "$(gate_status factory-qc-flow)" == "pass" ]]; then
    [[ -x Scripts/notchagent-desk-factory-qc.sh &&
       -x Scripts/notchagent-desk-factory-report-gate.sh &&
       -x firmware/notchagent_desk/verify-release.sh ]] || {
        echo "INVALID: factory QC executables are incomplete." >&2
        exit 1
    }
    zsh -n Scripts/notchagent-desk-factory-qc.sh Scripts/notchagent-desk-factory-report-gate.sh
    firmware/notchagent_desk/verify-release.sh firmware/notchagent_desk/release >/dev/null
    jq -e --slurpfile release "$release_contract" '
      .firmwareVersion == $release[0].firmwareVersion
    ' firmware/notchagent_desk/release/manifest.json >/dev/null || {
        echo "INVALID: packaged factory firmware does not match the Beta 1 release contract." >&2
        exit 1
    }
fi

if [[ "$(gate_status bom-enclosure-cable-freeze)" == "pass" ]]; then
    commercial_evidence=$(require_evidence_file bom-enclosure-cable-freeze)
    jq -e '
      .schemaVersion == 2 and .gate == "commercial-lot-freeze" and .result == "pass" and
      (keys | sort) == (["schemaVersion","gate","result","lotAlias","plannedUnits",
        "acceptedUnits","procurementFile","procurementSHA256","factoryReportFiles",
        "factoryReportSHA256s"] | sort) and
      (.lotAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
      .plannedUnits >= 5 and .plannedUnits == (.plannedUnits | floor) and
      .acceptedUnits >= .plannedUnits and
      (.procurementFile | type == "string" and length > 0) and
      (.procurementSHA256 | test("^[0-9a-f]{64}$")) and
      (.factoryReportFiles | type) == "array" and
      (.factoryReportFiles | length) == .acceptedUnits and
      all(.factoryReportFiles[]; type == "string" and length > 0) and
      ([.factoryReportFiles[]] | unique | length) == .acceptedUnits and
      (.factoryReportSHA256s | type) == "array" and
      (.factoryReportSHA256s | length) == .acceptedUnits and
      ([.factoryReportSHA256s[]] | unique | length) == .acceptedUnits and
      all(.factoryReportSHA256s[]; test("^[0-9a-f]{64}$"))
    ' "$commercial_evidence" >/dev/null || {
        echo "INVALID: commercial lot evidence does not satisfy the gate." >&2
        exit 1
    }
    procurement_file=$(jq -r '.procurementFile' "$commercial_evidence")
    [[ -f "$procurement_file" && ! -L "$procurement_file" &&
       "$(shasum -a 256 "$procurement_file" | awk '{print $1}')" ==
       "$(jq -r '.procurementSHA256' "$commercial_evidence")" ]] || {
        echo "INVALID: commercial procurement source is missing, linked, or changed." >&2
        exit 1
    }
    factory_report_files=("${(@f)$(jq -r '.factoryReportFiles[]' "$commercial_evidence")}")
    factory_report_shas=("${(@f)$(jq -r '.factoryReportSHA256s[]' "$commercial_evidence")}")
    for (( index = 1; index <= ${#factory_report_files}; index++ )); do
        report_file="${factory_report_files[$index]}"
        [[ -f "$report_file" && ! -L "$report_file" &&
           "$(shasum -a 256 "$report_file" | awk '{print $1}')" ==
           "${factory_report_shas[$index]}" ]] || {
            echo "INVALID: commercial factory source is missing, linked, or changed: $report_file" >&2
            exit 1
        }
    done
    recomputed_commercial=$(Scripts/notchagent-desk-commercial-lot-gate.sh \
      "$procurement_file" "${factory_report_files[@]}") || {
        echo "INVALID: commercial lot sources no longer satisfy the release gate." >&2
        exit 1
    }
    jq -e --argjson recomputed "$recomputed_commercial" '. == $recomputed' \
      "$commercial_evidence" >/dev/null || {
        echo "INVALID: commercial lot summary differs from its source evidence." >&2
        exit 1
    }
fi

if [[ "$(gate_status local-signed-recovery)" == "pass" ]]; then
    recovery_evidence=$(require_evidence_file local-signed-recovery)
    jq -e '
      .schemaVersion == 2 and .gate == "local-signed-recovery" and .result == "pass" and
      (keys | sort) == (["schemaVersion","gate","result","startedAt","completedAt","durationSeconds",
        "appVersion","buildNumber","firmwareVersion","protocolVersion","signatureKind","hardenedRuntime",
        "usbReenumerated","telemetryHealthy","telemetryReport","telemetrySHA256","packageManifestSHA256",
        "executableSHA256","telemetry"] | sort) and
      .appVersion == "3.1.2" and .buildNumber == "5" and
      .firmwareVersion == "0.6.16" and .protocolVersion == "1.1" and
      .signatureKind == "Developer ID Application" and .hardenedRuntime == true and
      .usbReenumerated == true and .telemetryHealthy == true and
      (.durationSeconds | type) == "number" and .durationSeconds > 0 and .durationSeconds <= 120 and
      (.telemetrySHA256 | test("^[0-9a-f]{64}$")) and
      (.packageManifestSHA256 | test("^[0-9a-f]{64}$")) and
      (.executableSHA256 | test("^[0-9a-f]{64}$")) and
      (.telemetry | keys | sort) == (["sampleCount","firmwareVersion","minimumFramesPerSecond","minimumFreeHeapBytes",
        "maximumInvalidFrameCount","maximumTouchReadErrorCount","touchControllerPresentEverySample",
        "resetReasons"] | sort) and
      .telemetry.sampleCount >= 2 and .telemetry.firmwareVersion == "0.6.16" and
      .telemetry.minimumFramesPerSecond >= 7 and
      .telemetry.minimumFreeHeapBytes >= 122880 and
      .telemetry.maximumInvalidFrameCount == 0 and .telemetry.maximumTouchReadErrorCount == 0 and
      .telemetry.touchControllerPresentEverySample == true and
      (.telemetry.resetReasons | index("usb")) != null and
      (.startedAt | fromdateiso8601) <= (.completedAt | fromdateiso8601)
    ' "$recovery_evidence" >/dev/null || {
        echo "INVALID: local-signed-recovery evidence does not satisfy the gate." >&2
        exit 1
    }
    recovery_telemetry_report=$(jq -r '.telemetryReport' "$recovery_evidence")
    [[ -f "$recovery_telemetry_report" && ! -L "$recovery_telemetry_report" &&
       "$(shasum -a 256 "$recovery_telemetry_report" | awk '{print $1}')" ==
       "$(jq -r '.telemetrySHA256' "$recovery_evidence")" ]] || {
        echo "INVALID: signed recovery telemetry source is missing, linked, or changed." >&2
        exit 1
    }
    recomputed_recovery_telemetry=$(Scripts/notchagent-desk-telemetry-evidence.sh \
      "$recovery_telemetry_report") || {
        echo "INVALID: signed recovery telemetry source is unhealthy." >&2
        exit 1
    }
    jq -e --argjson recomputed "$recomputed_recovery_telemetry" '.telemetry == $recomputed' \
      "$recovery_evidence" >/dev/null || {
        echo "INVALID: signed recovery telemetry differs from its source." >&2
        exit 1
    }
fi

touch_status=$(gate_status physical-touch-latency)
if [[ "$touch_status" == "pass" ]]; then
    touch_evidence=$(require_evidence_file physical-touch-latency)
    jq -e '
      .schemaVersion == 1 and .gate == "physical-touch-latency" and
      .status == "pass" and
      .firmwareVersion == "0.6.16" and
      .touchControllerPresent == true and
      .touchCount > 0 and
      (.touchInterruptCount > 0 or .touchPollTouchCount > 0) and
      .touchReadErrorCount == 0 and
      .maximumTouchLatencyMs <= .maximumAllowedTouchLatencyMs and
      .maximumAllowedTouchLatencyMs == 100 and
      .physicalChecks == {tap:"pass",swipeLeft:"pass",swipeRight:"pass",runnerJump:"pass"} and
      (.sourceReportSHA256 | test("^[0-9a-f]{64}$")) and
      (.reliabilityFailures | length) == 0
    ' "$touch_evidence" >/dev/null || {
        echo "INVALID: physical-touch-latency evidence does not satisfy the gate." >&2
        exit 1
    }
    touch_source=$(jq -r '.sourceReport' "$touch_evidence")
    [[ -f "$touch_source" && ! -L "$touch_source" &&
       "$(shasum -a 256 "$touch_source" | awk '{print $1}')" ==
       "$(jq -r '.sourceReportSHA256' "$touch_evidence")" ]] || {
        echo "INVALID: physical touch source report is missing or has changed." >&2
        exit 1
    }
    recomputed_touch=$(Scripts/notchagent-desk-touch-summary.sh "$touch_source" \
      "$(jq -r '.physicalChecks.tap' "$touch_evidence")" \
      "$(jq -r '.physicalChecks.swipeLeft' "$touch_evidence")" \
      "$(jq -r '.physicalChecks.swipeRight' "$touch_evidence")" \
      "$(jq -r '.physicalChecks.runnerJump' "$touch_evidence")" \
      "$touch_source") || {
        echo "INVALID: physical touch source no longer satisfies the gate." >&2
        exit 1
    }
    jq -e --argjson recomputed "$recomputed_touch" '. == $recomputed' \
      "$touch_evidence" >/dev/null || {
        echo "INVALID: physical touch summary differs from its source report." >&2
        exit 1
    }
fi

if [[ "$(gate_status soak-24-hours)" == "pass" ]]; then
    soak_evidence=$(require_evidence_file soak-24-hours)
    jq -e --slurpfile package "$firmware_package_manifest" --slurpfile release "$release_contract" '
      .schemaVersion == 4 and .gate == "app-desk-soak" and .result == "pass" and
      .appVersion == $release[0].appVersion and .buildNumber == $release[0].buildNumber and
      .firmwareVersion == "0.6.16" and .durationSeconds >= 86400 and
      .firmwareVersion == $package[0].firmwareVersion and
      .firmwareImageSHA256 == $package[0].imageSHA256 and
      .firmwareSourceSHA256 == $package[0].sourceSHA256 and
      .samples >= 8640 and .maximumSampleGapMilliseconds <= 16000 and
      .wallClockDurationSeconds >= 86390 and .maximumWallClockGapSeconds <= 16 and
      (.firstCapturedAt | fromdateiso8601) <= (.lastCapturedAt | fromdateiso8601) and
      .connectionContinuity == true and
      .minimumFramesPerSecond >= 7 and .minimumFreeHeapBytes >= 122880 and
      .maximumInvalidFrameCount == 0 and .maximumTouchReadErrorCount == 0 and
      (.sourceReport | type == "string" and length > 0) and
      (.reportSHA256 | test("^[0-9a-f]{64}$"))
    ' "$soak_evidence" >/dev/null || {
        echo "INVALID: soak-24-hours evidence does not satisfy the gate." >&2
        exit 1
    }
    soak_source=$(jq -r '.sourceReport' "$soak_evidence")
    [[ -f "$soak_source" && ! -L "$soak_source" &&
       "$(shasum -a 256 "$soak_source" | awk '{print $1}')" ==
       "$(jq -r '.reportSHA256' "$soak_evidence")" ]] || {
        echo "INVALID: soak source report is missing, linked, or changed." >&2
        exit 1
    }
    recomputed_soak=$(Scripts/notchagent-desk-soak-evidence.sh "$soak_source" \
      "$(jq -r '.durationSeconds' "$soak_evidence")") || {
        echo "INVALID: soak source no longer satisfies the 24-hour gate." >&2
        exit 1
    }
    jq -e --argjson recomputed "$recomputed_soak" '. == $recomputed' \
      "$soak_evidence" >/dev/null || {
        echo "INVALID: soak summary differs from its source report." >&2
        exit 1
    }
fi

if [[ "$(gate_status soak-24-hours)" == "waived" ]]; then
    soak_waiver=$(require_evidence_file soak-24-hours)
    jq -e '
      .schemaVersion == 1 and .gate == "soak-24-hours" and .result == "waived" and
      .authority == "product-owner" and .directive == "assume-pass-and-proceed" and
      (.waivedAt | fromdateiso8601 | type) == "number" and
      .observedDurationSeconds >= 3600 and .samples >= 900 and
      .firmwareVersion == "0.6.16" and .connectionContinuityDuringObservedWindow == true and
      .minimumFramesPerSecond >= 7 and .minimumFreeHeapBytes >= 122880 and
      .maximumInvalidFrameCount == 0 and .maximumTouchReadErrorCount == 0 and
      .reliabilityFailures == 0 and
      (.sourceReport | type == "string" and startswith("docs/evidence/")) and
      (.reportSHA256 | test("^[0-9a-f]{64}$")) and
      .limitation == "The 24-hour duration was not completed; risk was explicitly accepted by the product owner."
    ' "$soak_waiver" >/dev/null || {
        echo "INVALID: soak waiver is incomplete, unhealthy, or lacks explicit authority." >&2
        exit 1
    }
    soak_source=$(jq -r '.sourceReport' "$soak_waiver")
    [[ -f "$soak_source" && ! -L "$soak_source" &&
       "$(shasum -a 256 "$soak_source" | awk '{print $1}')" ==
       "$(jq -r '.reportSHA256' "$soak_waiver")" ]] || {
        echo "INVALID: waived soak source report is missing, linked, or changed." >&2
        exit 1
    }
    jq -s -e --slurpfile waiver "$soak_waiver" '
      [.[] | select(.telemetry != null)] as $samples |
      ($samples | map(.capturedAt | fromdateiso8601)) as $times |
      ($samples | length) == $waiver[0].samples and
      ($times[-1] - $times[0]) >= 3600 and
      all($samples[]; .phase == "connected" and (.reliabilityFailures | length) == 0) and
      ($samples | map(.telemetry.framesPerSecond) | min) == $waiver[0].minimumFramesPerSecond and
      ($samples | map(.telemetry.minimumFreeHeapBytes) | min) == $waiver[0].minimumFreeHeapBytes and
      ($samples | map(.telemetry.invalidFrameCount) | max) == 0 and
      ($samples | map(.telemetry.touchReadErrorCount // 0) | max) == 0
    ' "$soak_source" >/dev/null || {
        echo "INVALID: observed soak window does not support its waiver summary." >&2
        exit 1
    }
fi

if [[ "$(gate_status physical-touch-latency)" == "waived" ]]; then
    touch_waiver=$(require_evidence_file physical-touch-latency)
    jq -e '
      .schemaVersion == 1 and .gate == "physical-touch-latency" and .result == "waived" and
      .authority == "product-owner" and .directive == "assume-pass-and-proceed" and
      (.waivedAt | fromdateiso8601 | type) == "number" and
      (.supportingEvidence | length) == 2 and
      all(.supportingEvidence[];
        (.file | type == "string" and startswith("docs/evidence/")) and
        (.sha256 | test("^[0-9a-f]{64}$"))) and
      .touchControllerPresentDuringReconnects == true and .maximumTouchReadErrorCount == 0 and
      .limitation == "Physical touch latency was not measured; risk was explicitly accepted by the product owner."
    ' "$touch_waiver" >/dev/null || {
        echo "INVALID: physical touch waiver is incomplete or lacks explicit authority." >&2
        exit 1
    }
    for evidence_row in "${(@f)$(jq -r '.supportingEvidence[] | [.file,.sha256] | @tsv' "$touch_waiver")}"; do
        IFS=$'\t' read -r supporting_file supporting_sha <<<"$evidence_row"
        [[ -f "$supporting_file" && ! -L "$supporting_file" &&
           "$(shasum -a 256 "$supporting_file" | awk '{print $1}')" == "$supporting_sha" ]] || {
            echo "INVALID: physical touch waiver supporting evidence is missing, linked, or changed." >&2
            exit 1
        }
    done
    jq -e '.gate == "ai-visual-review" and .result == "pass" and .generatedImagery == false' \
      "$(jq -r '.supportingEvidence[0].file' "$touch_waiver")" >/dev/null || {
        echo "INVALID: physical touch waiver lacks a live visual review." >&2
        exit 1
    }
    jq -e '.gate == "physical-reset-usb-reconnect" and .result == "pass" and
      .cycles == 100 and .touchControllerPresentEveryCycle == true and
      .maximumTouchReadErrorCount == 0' \
      "$(jq -r '.supportingEvidence[1].file' "$touch_waiver")" >/dev/null || {
        echo "INVALID: physical touch waiver lacks healthy controller evidence." >&2
        exit 1
    }
fi

for waived_gate in abrupt-power-recovery dock-hub-mac-matrix; do
    if [[ "$(gate_status "$waived_gate")" == "waived" ]]; then
        hardware_waiver=$(require_evidence_file "$waived_gate")
        jq -e --arg gate "$waived_gate" '
          .schemaVersion == 1 and .gate == $gate and .result == "waived" and
          .authority == "product-owner" and .directive == "assume-pass-and-proceed" and
          (.waivedAt | fromdateiso8601 | type) == "number" and
          (.supportingEvidence | length) == 2 and
          all(.supportingEvidence[];
            (.file | type == "string" and startswith("docs/evidence/")) and
            (.sha256 | test("^[0-9a-f]{64}$"))) and
          (.limitation | type == "string" and contains("risk was explicitly accepted by the product owner."))
        ' "$hardware_waiver" >/dev/null || {
            echo "INVALID: $waived_gate waiver is incomplete or lacks explicit authority." >&2
            exit 1
        }
        for evidence_row in "${(@f)$(jq -r '.supportingEvidence[] | [.file,.sha256] | @tsv' "$hardware_waiver")}"; do
            IFS=$'\t' read -r supporting_file supporting_sha <<<"$evidence_row"
            [[ -f "$supporting_file" && ! -L "$supporting_file" &&
               "$(shasum -a 256 "$supporting_file" | awk '{print $1}')" == "$supporting_sha" ]] || {
                echo "INVALID: $waived_gate supporting evidence is missing, linked, or changed." >&2
                exit 1
            }
        done
        jq -e '.gate == "local-signed-recovery" and .result == "pass"' \
          "$(jq -r '.supportingEvidence[0].file' "$hardware_waiver")" >/dev/null || exit 1
        jq -e '.gate == "physical-reset-usb-reconnect" and .result == "pass" and .cycles == 100' \
          "$(jq -r '.supportingEvidence[1].file' "$hardware_waiver")" >/dev/null || exit 1
    fi
done

if [[ "$(gate_status bom-enclosure-cable-freeze)" == "waived" ]]; then
    bom_waiver=$(require_evidence_file bom-enclosure-cable-freeze)
    jq -e '
      .schemaVersion == 1 and .gate == "bom-enclosure-cable-freeze" and
      .result == "waived" and .authority == "product-owner" and
      .directive == "commodity-components-no-fixed-sku" and
      (.waivedAt | fromdateiso8601 | type) == "number" and
      .requirementsRetained == [
        "USB cable must support data transfer",
        "enclosure must preserve connector, touch, ventilation, and boot access",
        "functional compatibility remains part of unit QC"
      ] and
      (.limitation | type == "string" and
        contains("risk was explicitly accepted by the product owner."))
    ' "$bom_waiver" >/dev/null || {
        echo "INVALID: BOM waiver is incomplete or lacks explicit authority and functional requirements." >&2
        exit 1
    }
fi

unsupported_waiver=$(jq -r '.gates[] | select(.status == "waived" and
  (.id != "soak-24-hours" and .id != "physical-touch-latency" and
   .id != "abrupt-power-recovery" and .id != "dock-hub-mac-matrix" and
   .id != "bom-enclosure-cable-freeze")) | .id' "$status_file")
[[ -z "$unsupported_waiver" ]] || {
    echo "INVALID: unsupported release-gate waiver: $unsupported_waiver" >&2
    exit 1
}

if [[ "$(gate_status abrupt-power-recovery)" == "pass" ]]; then
    power_evidence=$(require_evidence_file abrupt-power-recovery)
    jq -e --slurpfile package "$firmware_package_manifest" '
      .schemaVersion == 3 and .gate == "abrupt-power-recovery" and .result == "pass" and
      (keys | sort) == (["schemaVersion","gate","result","startedAt","disconnectedAt","reconnectedAt",
        "completedAt","disconnectObservedAfterSeconds","reconnectSeconds","firmwareVersion",
        "protocolVersion","firmwareImageSHA256","firmwareSourceSHA256","usbReenumerated",
        "telemetryHealthy","telemetryReport","telemetrySHA256","telemetry"] | sort) and
      .firmwareVersion == "0.6.16" and .protocolVersion == "1.1" and
      .firmwareVersion == $package[0].firmwareVersion and
      .firmwareImageSHA256 == $package[0].imageSHA256 and
      .firmwareSourceSHA256 == $package[0].sourceSHA256 and
      .usbReenumerated == true and .telemetryHealthy == true and
      .disconnectObservedAfterSeconds > 0 and .disconnectObservedAfterSeconds <= 120 and
      .reconnectSeconds > 0 and .reconnectSeconds <= 120 and
      (.telemetrySHA256 | test("^[0-9a-f]{64}$")) and
      (.telemetry | keys | sort) == (["sampleCount","firmwareVersion","minimumFramesPerSecond","minimumFreeHeapBytes",
        "maximumInvalidFrameCount","maximumTouchReadErrorCount","touchControllerPresentEverySample",
        "resetReasons"] | sort) and
      .telemetry.sampleCount >= 2 and .telemetry.firmwareVersion == "0.6.16" and
      .telemetry.minimumFramesPerSecond >= 7 and
      .telemetry.minimumFreeHeapBytes >= 122880 and
      .telemetry.maximumInvalidFrameCount == 0 and .telemetry.maximumTouchReadErrorCount == 0 and
      .telemetry.touchControllerPresentEverySample == true and
      (.telemetry.resetReasons | index("power_on")) != null and
      (.startedAt | fromdateiso8601) <= (.disconnectedAt | fromdateiso8601) and
      (.disconnectedAt | fromdateiso8601) < (.reconnectedAt | fromdateiso8601) and
      (.reconnectedAt | fromdateiso8601) <= (.completedAt | fromdateiso8601)
    ' "$power_evidence" >/dev/null || {
        echo "INVALID: abrupt-power-recovery evidence does not satisfy the gate." >&2
        exit 1
    }
    power_telemetry_report=$(jq -r '.telemetryReport' "$power_evidence")
    [[ -f "$power_telemetry_report" && ! -L "$power_telemetry_report" &&
       "$(shasum -a 256 "$power_telemetry_report" | awk '{print $1}')" ==
       "$(jq -r '.telemetrySHA256' "$power_evidence")" ]] || {
        echo "INVALID: abrupt-power telemetry source is missing, linked, or changed." >&2
        exit 1
    }
    recomputed_power_telemetry=$(Scripts/notchagent-desk-telemetry-evidence.sh \
      "$power_telemetry_report" power_on) || {
        echo "INVALID: abrupt-power telemetry source is unhealthy or lacks power_on reset." >&2
        exit 1
    }
    jq -e --argjson recomputed "$recomputed_power_telemetry" '.telemetry == $recomputed' \
      "$power_evidence" >/dev/null || {
        echo "INVALID: abrupt-power telemetry differs from its source." >&2
        exit 1
    }
fi

if [[ "$(gate_status dock-hub-mac-matrix)" == "pass" ]]; then
    Scripts/notchagent-desk-matrix-gate.sh "$(require_evidence_file dock-hub-mac-matrix)" >/dev/null
fi

if [[ "$(gate_status developer-id-notarization)" == "pass" ]]; then
    notarization_evidence=$(require_evidence_file developer-id-notarization)
    expected_app_version=$(jq -r '.appVersion' "$release_contract")
    expected_build_number=$(jq -r '.buildNumber' "$release_contract")
    jq -e --arg appVersion "$expected_app_version" --arg buildNumber "$expected_build_number" '
      .schemaVersion == 2 and .gate == "developer-id-notarization" and .result == "pass" and
      (keys | sort) == (["schemaVersion","gate","result","completedAt","bundleIdentifier",
        "appVersion","buildNumber","signatureKind","hardenedRuntime","notarizationStatus",
        "stapleValidated","gatekeeperAccepted","executableSHA256","releaseAssetFilename",
        "releaseAssetSHA256"] | sort) and
      .bundleIdentifier == "br.com.lfrprojects.notchagent" and
      .appVersion == $appVersion and .buildNumber == $buildNumber and
      .signatureKind == "Developer ID Application" and .hardenedRuntime == true and
      .notarizationStatus == "Accepted" and .stapleValidated == true and
      .gatekeeperAccepted == true and
      (.executableSHA256 | test("^[0-9a-f]{64}$")) and
      .releaseAssetFilename == "NotchAgent-Desk-Beta1-3.1.2.zip" and
      (.releaseAssetSHA256 | test("^[0-9a-f]{64}$")) and
      (.completedAt | fromdateiso8601 | type) == "number"
    ' "$notarization_evidence" >/dev/null || {
        echo "INVALID: developer-id-notarization evidence does not satisfy the gate." >&2
        exit 1
    }
fi

if [[ "$(gate_status onboarding-qr)" == "pass" ]]; then
    onboarding_evidence=$(require_evidence_file onboarding-qr)
    expected_app_version=$(jq -r '.appVersion' "$release_contract")
    jq -e --arg version "$expected_app_version" '
      .schemaVersion == 3 and .gate == "onboarding-qr" and .result == "pass" and
      (keys | sort) == (["schemaVersion","gate","result","verifiedAt","url","qrFile",
        "qrSHA256","publishedCommitSHA","guideHTTPStatus","guideContentSHA256",
        "releaseAssetURL","releaseAssetSHA256","notarizationEvidenceSHA256",
        "verificationMethod","developerIDSigned","notarized","downloadedExecutableSHA256",
        "downloadedFirmwareManifestSHA256","artifactSignatureVerified","artifactStapleValidated",
        "artifactGatekeeperAccepted","artifactFirmwareVerified"] | sort) and
      .verificationMethod == "live-download" and
      .url == "https://github.com/luisroquette/notchagent/blob/master/docs/NOTCHAGENT_DESK_ONBOARDING.md" and
      .qrFile == "docs/img/notchagent-desk-onboarding-qr.svg" and
      (.qrSHA256 | test("^[0-9a-f]{64}$")) and
      (.publishedCommitSHA | test("^[0-9a-f]{40}$")) and
      .guideHTTPStatus == 200 and (.guideContentSHA256 | test("^[0-9a-f]{64}$")) and
      .releaseAssetURL == ("https://github.com/luisroquette/notchagent/releases/download/v" + $version +
        "/NotchAgent-Desk-Beta1-" + $version + ".zip") and
      (.releaseAssetSHA256 | test("^[0-9a-f]{64}$")) and
      (.notarizationEvidenceSHA256 | test("^[0-9a-f]{64}$")) and
      (.downloadedExecutableSHA256 | test("^[0-9a-f]{64}$")) and
      (.downloadedFirmwareManifestSHA256 | test("^[0-9a-f]{64}$")) and
      .artifactSignatureVerified == true and .artifactStapleValidated == true and
      .artifactGatekeeperAccepted == true and .artifactFirmwareVerified == true and
      .developerIDSigned == true and .notarized == true and
      (.verifiedAt | fromdateiso8601 | type) == "number"
    ' "$onboarding_evidence" >/dev/null || {
        echo "INVALID: onboarding publication evidence does not satisfy the gate." >&2
        exit 1
    }
    qr_file=$(jq -r '.qrFile' "$onboarding_evidence")
    actual_qr_sha=$(shasum -a 256 "$qr_file" | awk '{print $1}')
    [[ "$actual_qr_sha" == "$(jq -r '.qrSHA256' "$onboarding_evidence")" ]] || {
        echo "INVALID: onboarding QR hash does not match publication evidence." >&2
        exit 1
    }
    Scripts/notchagent-desk-onboarding-qr-gate.swift \
      "$qr_file" docs/NOTCHAGENT_DESK_ONBOARDING_URL.txt >/dev/null || exit 1
fi

if [[ "$(gate_status developer-id-notarization)" == "pass" &&
      "$(gate_status onboarding-qr)" == "pass" ]]; then
    notarization_evidence=$(require_evidence_file developer-id-notarization)
    onboarding_evidence=$(require_evidence_file onboarding-qr)
    [[ "$(jq -r '.releaseAssetSHA256' "$notarization_evidence")" ==
       "$(jq -r '.releaseAssetSHA256' "$onboarding_evidence")" ]] || {
        echo "INVALID: published onboarding asset is not the notarized release asset." >&2
        exit 1
    }
    [[ "$(shasum -a 256 "$notarization_evidence" | awk '{print $1}')" ==
       "$(jq -r '.notarizationEvidenceSHA256' "$onboarding_evidence")" ]] || {
        echo "INVALID: onboarding evidence is not bound to the notarization record." >&2
        exit 1
    }
    [[ "$(jq -r '.executableSHA256' "$notarization_evidence")" ==
       "$(jq -r '.downloadedExecutableSHA256' "$onboarding_evidence")" ]] || {
        echo "INVALID: published executable is not the notarized executable." >&2
        exit 1
    }
fi

if [[ "$(gate_status local-signed-recovery)" == "pass" &&
      "$(gate_status developer-id-notarization)" == "pass" ]]; then
    recovery_evidence=$(require_evidence_file local-signed-recovery)
    notarization_evidence=$(require_evidence_file developer-id-notarization)
    [[ "$(jq -r '.executableSHA256' "$recovery_evidence")" ==
       "$(jq -r '.executableSHA256' "$notarization_evidence")" ]] || {
        echo "INVALID: signed recovery did not run with the notarized executable." >&2
        exit 1
    }
fi

if [[ "$(gate_status local-signed-recovery)" == "pass" &&
      "$(gate_status onboarding-qr)" == "pass" ]]; then
    recovery_evidence=$(require_evidence_file local-signed-recovery)
    onboarding_evidence=$(require_evidence_file onboarding-qr)
    [[ "$(jq -r '.packageManifestSHA256' "$recovery_evidence")" ==
       "$(jq -r '.downloadedFirmwareManifestSHA256' "$onboarding_evidence")" ]] || {
        echo "INVALID: signed recovery firmware package differs from the published app package." >&2
        exit 1
    }
fi

if [[ "$(gate_status five-user-seven-day-pilot)" == "pass" ]]; then
    Scripts/notchagent-desk-pilot-gate.sh "$(require_evidence_file five-user-seven-day-pilot)" >/dev/null
fi

pending=$(jq -r '.gates[] | select(.status != "pass" and .status != "waived") | "\(.id): \(.status) — \(.evidence)"' "$status_file")
if [[ -n "$pending" ]]; then
    echo "NOT READY: NotchAgent Desk Beta 1 has open gates:" >&2
    print -r -- "$pending" >&2
    exit 1
fi

echo "PASS: every NotchAgent Desk Beta 1 release gate has evidence."
