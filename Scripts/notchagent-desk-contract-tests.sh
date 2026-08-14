#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

test_dir=$(mktemp -d -t notchagent-desk-contracts)
[[ -n "$test_dir" && "$test_dir" == /var/folders/*/T/* ]] || exit 1
status_fixture="Tests/NotchAgentTests/Fixtures/notchagent-desk-beta1-status.json"
[[ -f "$status_fixture" && ! -L "$status_fixture" ]] || exit 1
cleanup() {
    [[ -n "$test_dir" && -d "$test_dir" && "$test_dir" == /var/folders/*/T/* ]] || return 0
    rm -r -- "$test_dir"
}
trap cleanup EXIT

Scripts/notchagent-desk-onboarding-qr-gate.swift \
  docs/img/notchagent-desk-onboarding-qr.svg \
  docs/NOTCHAGENT_DESK_ONBOARDING_URL.txt >/dev/null

ai_visual_evidence="${NOTCHAGENT_DESK_AI_VISUAL_EVIDENCE:-docs/evidence/notchagent-desk-beta1-ai-visual-review-20260814T185112Z.json}"
if [[ -e "$ai_visual_evidence" ]]; then
    Scripts/notchagent-desk-ai-visual-review-gate.sh "$ai_visual_evidence" >/dev/null
else
    echo "SKIP: local AI visual-review evidence is not part of the public source checkout."
fi
rg -q 'build_number=.*buildNumber' Scripts/notchagent-desk-publication-evidence.sh || {
    echo "FAIL: publication evidence must validate the release-contract build number." >&2
    exit 1
}
rg -q '\-o "\$output_dir/\$feed_filename"' Scripts/generate-update-appcast.sh || {
    echo "FAIL: appcast generator must write inside its validated output directory." >&2
    exit 1
}

unit_label="$test_dir/unit-label.svg"
Scripts/notchagent-desk-unit-label.sh "$unit_label" BETA1-LOT-A DESK-B1-001 >/dev/null
rg -q 'DESK-B1-001' "$unit_label" &&
  rg -q 'LOT BETA1-LOT-A' "$unit_label" &&
  rg -q 'FW 0.6.16' "$unit_label" || {
    echo "FAIL: factory label lost its sanitized release identity." >&2
    exit 1
}
if rg -qi 'serial|mac address|customer|credential|usbmodem' "$unit_label"; then
    echo "FAIL: factory label exposes a forbidden identifier field." >&2
    exit 1
fi

for onboarding_phrase in \
    'charge-only cable' \
    'Recovery without Terminal' \
    'No PIN is needed' \
    'Do not press unidentified board buttons' \
    'touch latency below 100 ms'; do
    rg -Fq "$onboarding_phrase" docs/NOTCHAGENT_DESK_ONBOARDING.md || {
        echo "FAIL: onboarding lost required recovery guidance: $onboarding_phrase" >&2
        exit 1
    }
done

if rg -n 'privacy: \.public' Sources/NotchAgent/Features/Desk >/dev/null; then
    echo "FAIL: Desk logs expose dynamic values publicly." >&2
    exit 1
fi
for evidence_script in Scripts/notchagent-desk-recovery.sh Scripts/notchagent-desk-soak-evidence.sh; do
    rg -q '\$PWD/' "$evidence_script" || {
        echo "FAIL: $evidence_script must redact repository-absolute evidence paths." >&2
        exit 1
    }
done
rg -q 'ambient intelligence contains a network/API dependency' \
  Scripts/notchagent-desk-beta1-gate.sh || {
    echo "FAIL: Beta gate does not enforce local-only ambient intelligence." >&2
    exit 1
}
rg -q 'sanitized diagnostic schema exposes a forbidden identifier or secret' \
  Scripts/notchagent-desk-beta1-gate.sh || {
    echo "FAIL: Beta gate does not enforce sanitized diagnostic schema privacy." >&2
    exit 1
}

rg -q 'if \(!hadInterrupt && !shouldProbe\) return;' firmware/notchagent_desk/touch.h &&
  rg -q 'if \(!hadInterrupt\) \{' firmware/notchagent_desk/touch.h &&
  rg -q 'controllerPresent_ = present;' firmware/notchagent_desk/touch.h || {
    echo "FAIL: touch coordinate reads are no longer IRQ-driven." >&2
    exit 1
}

rg -q 'static const uint8_t command\[8\] = \{0xB5, 0xAB, 0xA5, 0x5A, 0, 0, 0, 8\};' \
  firmware/notchagent_desk/touch.h || {
    echo "FAIL: touch driver differs from the board's validated 8-byte AXS15231B command." >&2
    exit 1
}
rg -q 'elapsedSinceInterrupt < DESK_TOUCH_SETTLE_US' firmware/notchagent_desk/touch.h || {
    echo "FAIL: touch driver can read coordinates before the IRQ data settles." >&2
    exit 1
}

if rg -q 'command\[11\]|contactPresent = response\[1\]' firmware/notchagent_desk/touch.h; then
    echo "FAIL: touch driver reintroduced the frame that caused phantom IRQ input." >&2
    exit 1
fi

rg -q 'activeRenderIntervalCount >= 3' firmware/notchagent_desk/notchagent_desk.ino &&
  rg -q 'interval > 0 && interval <= 250' firmware/notchagent_desk/notchagent_desk.ino || {
    echo "FAIL: sparse static redraws can again masquerade as low active FPS." >&2
    exit 1
}

for build_script in firmware/notchagent_desk/build.sh firmware/notchagent_desk/package-release.sh; do
    rg -q 'tools\.ctags\.pattern=.*consume-stdin\.sh' "$build_script" || {
        echo "FAIL: $build_script still depends on nondeterministic Arduino prototype generation." >&2
        exit 1
    }
    rg -q 'arduino-cli compile --jobs 4' "$build_script" || {
        echo "FAIL: $build_script can reintroduce the Arduino library-detection race." >&2
        exit 1
    }
done
[[ -x firmware/notchagent_desk/consume-stdin.sh ]] || {
    echo "FAIL: deterministic Arduino stdin consumer is not executable." >&2
    exit 1
}
rg -q 'while IFS= read -r _' firmware/notchagent_desk/consume-stdin.sh || {
    echo "FAIL: Arduino prototype bypass can stop consuming compiler output and deadlock." >&2
    exit 1
}
[[ -x firmware/notchagent_desk/verify-toolchain.sh ]] || {
    echo "FAIL: pinned firmware toolchain verifier is unavailable." >&2
    exit 1
}
for build_script in firmware/notchagent_desk/build.sh firmware/notchagent_desk/package-release.sh; do
    rg -q 'verify-toolchain\.sh' "$build_script" || {
        echo "FAIL: $build_script does not fail closed on firmware toolchain drift." >&2
        exit 1
    }
done
rg -q 'consume-stdin\.sh package-release\.sh package_manifest\.swift partitions\.csv touch\.h' \
    firmware/notchagent_desk/package-release.sh || {
    echo "FAIL: firmware fingerprint excludes the build recipe or partition table." >&2
    exit 1
}
rg -q 'trim_factory\.swift verify-toolchain\.sh' \
    firmware/notchagent_desk/package-release.sh || {
    echo "FAIL: firmware fingerprint excludes image trimming or toolchain validation." >&2
    exit 1
}
mock_bin="$test_dir/mock-bin"
mkdir "$mock_bin"
mock_cli="$mock_bin/arduino-cli"
print -r -- '#!/bin/sh
case "$1" in
  version) printf '\''{"VersionString":"1.5.2"}\n'\'' ;;
  core) printf '\''{"platforms":[{"id":"esp32:esp32","installed_version":"3.3.8"}]}\n'\'' ;;
  lib) printf '\''{"installed_libraries":[
    {"library":{"name":"lvgl","version":"9.2.2"}},
    {"library":{"name":"GFX Library for Arduino","version":"1.6.5"}},
    {"library":{"name":"ArduinoJson","version":"7.2.0"}}
  ]}\n'\'' ;;
  *) exit 2 ;;
esac' > "$mock_cli"
chmod 755 "$mock_cli"
if PATH="$mock_bin:$PATH" firmware/notchagent_desk/verify-toolchain.sh >/dev/null 2>&1; then
    echo "FAIL: firmware toolchain verifier accepted a drifting Arduino CLI." >&2
    exit 1
fi
rg -q 'version: 1.5.1' .github/workflows/notchagent-desk.yml || {
    echo "FAIL: Desk CI does not install the pinned Arduino CLI 1.5.1." >&2
    exit 1
}
rg -q 'version: 1.5.1' .github/workflows/sync-to-public.yml || {
    echo "FAIL: public sync does not install the pinned Arduino CLI 1.5.1." >&2
    exit 1
}
for workflow in .github/workflows/notchagent-desk.yml .github/workflows/sync-to-public.yml; do
    rg -q 'NOTCHAGENT_DISABLE_PAID_PROBES: "1"' "$workflow" || {
        echo "FAIL: $workflow can validate Desk with paid probes enabled." >&2
        exit 1
    }
done
for workflow in .github/workflows/sync-to-public.yml .github/workflows/public-release-security.yml; do
    rg -q 'NOTCHAGENT_PUBLIC_HISTORY_BASE: refs/remotes/public-audit/master' "$workflow" || {
        echo "FAIL: $workflow does not block personal identifiers in newly published history." >&2
        exit 1
    }
done
NOTCHAGENT_PUBLIC_HISTORY_BASE=HEAD Scripts/audit-public-release.sh >/dev/null

[[ -x Scripts/make-notchagent-desk-local-beta1.sh ]] || {
    echo "FAIL: deterministic local Beta 1 app builder is unavailable." >&2
    exit 1
}
for publication_guard in 'codesign --verify --deep --strict' 'xcrun stapler validate' \
  'spctl --assess --type execute' 'verify-release.sh "$downloaded_firmware"' \
  'downloaded_executable_sha'; do
    rg -Fq "$publication_guard" Scripts/notchagent-desk-publication-evidence.sh || {
        echo "FAIL: public release verification lost guard: $publication_guard" >&2
        exit 1
    }
done
for candidate_field in appVersion buildNumber firmwareImageSHA256 firmwareSourceSHA256; do
    rg -q "$candidate_field" Scripts/notchagent-desk-soak-evidence.sh || {
        echo "FAIL: soak evidence does not bind candidate field $candidate_field." >&2
        exit 1
    }
done
for recovery_script in Scripts/notchagent-desk-power-cycle.sh Scripts/notchagent-desk-recovery.sh; do
    rg -q 'path collision; prior evidence was preserved' "$recovery_script" || {
        echo "FAIL: $recovery_script can overwrite prior physical evidence." >&2
        exit 1
    }
done
status_fixture_dir="$test_dir/soak-status"
mkdir "$status_fixture_dir"
status_fixture_report="$status_fixture_dir/soak.jsonl"
jq -nc '{capturedAt:"2026-08-13T17:00:00Z",elapsedMilliseconds:5000,phase:"connected",
  reliabilityFailures:["fps_below_threshold"],telemetry:{firmwareVersion:"0.6.16",uptimeSeconds:5,
  freeHeapBytes:160000,minimumFreeHeapBytes:150000,framesPerSecond:6.5,resetReason:"usb",
  invalidFrameCount:0,handshakeCount:1,touchCount:0,touchInterruptCount:0,touchReadErrorCount:0,
  touchPollAttemptCount:10,touchPollTouchCount:0,touchControllerPresent:true,
  lastTouchLatencyMs:0,maximumTouchLatencyMs:0}}' > "$status_fixture_report"
print -r -- "$$" > "$status_fixture_dir/soak-active.pid"
print -r -- "$status_fixture_report" > "$status_fixture_dir/soak-active-report.txt"
if NOTCHAGENT_DESK_REPORT_DIR="$status_fixture_dir" \
    Scripts/notchagent-desk-soak-status.sh >/dev/null 2>&1; then
    echo "FAIL: soak status reported healthy despite a reliability failure." >&2
    exit 1
fi

reconnect_fixture="$test_dir/reconnect-20260813T140000Z.json"
jq -n '[range(1; 3) as $cycle | {cycle:$cycle,reconnectMilliseconds:8000,
  resetMilliseconds:2000,telemetryMilliseconds:6000,
  telemetry:{firmwareVersion:"0.6.16",framesPerSecond:8.4,minimumFreeHeapBytes:162280,
    invalidFrameCount:0,touchReadErrorCount:0,touchControllerPresent:true,
    touchPollAttemptCount:179,uptimeSeconds:2,handshakeCount:1,resetReason:"usb"}}]' > "$reconnect_fixture"
reconnect_summary=$(Scripts/notchagent-desk-reconnect-evidence.sh "$reconnect_fixture" 2)
jq -e --slurpfile package firmware/notchagent_desk/release/manifest.json '
  .schemaVersion == 3 and .cycles == 2 and .firmwareVersion == "0.6.16" and
  .durationSeconds == 16 and .firmwareImageSHA256 == $package[0].imageSHA256 and
  .firmwareSourceSHA256 == $package[0].sourceSHA256
' \
    <<<"$reconnect_summary" >/dev/null
jq '.[1].cycle = 3' "$reconnect_fixture" > "$test_dir/reconnect-20260813T140001Z.json"
if Scripts/notchagent-desk-reconnect-evidence.sh \
    "$test_dir/reconnect-20260813T140001Z.json" 2 >/dev/null 2>&1; then
    echo "FAIL: reconnect evidence accepted non-sequential cycles." >&2
    exit 1
fi
stale_boot_reconnect="$test_dir/reconnect-20260813T140002Z.json"
jq '.[1].telemetry.uptimeSeconds = 31' "$reconnect_fixture" > "$stale_boot_reconnect"
if Scripts/notchagent-desk-reconnect-evidence.sh "$stale_boot_reconnect" 2 >/dev/null 2>&1; then
    echo "FAIL: reconnect evidence accepted telemetry from a device that did not reboot." >&2
    exit 1
fi
wrong_reset_reconnect="$test_dir/reconnect-20260813T140003Z.json"
jq '.[1].telemetry.resetReason = "power_on"' "$reconnect_fixture" > "$wrong_reset_reconnect"
if Scripts/notchagent-desk-reconnect-evidence.sh "$wrong_reset_reconnect" 2 >/dev/null 2>&1; then
    echo "FAIL: reconnect evidence accepted a cycle without a USB reset." >&2
    exit 1
fi
tampered_manifest="$test_dir/tampered-release-manifest.json"
jq '.imageSHA256 = ("f" * 64)' firmware/notchagent_desk/release/manifest.json > "$tampered_manifest"
tampered_summary=$(NOTCHAGENT_DESK_RELEASE_MANIFEST="$tampered_manifest" \
    Scripts/notchagent-desk-reconnect-evidence.sh "$reconnect_fixture" 2)
jq -e '.firmwareImageSHA256 == ("f" * 64)' <<<"$tampered_summary" >/dev/null || {
    echo "FAIL: reconnect evidence is not bound to its supplied firmware manifest." >&2
    exit 1
}

telemetry_contract="$test_dir/telemetry.jsonl"
for uptime in 5 10; do
    jq -nc --argjson uptime "$uptime" '{capturedAt:"2026-08-13T14:00:00Z",
      telemetry:{firmwareVersion:"0.6.16",framesPerSecond:8.4,minimumFreeHeapBytes:162280,
        invalidFrameCount:0,touchReadErrorCount:0,touchControllerPresent:true,
        resetReason:"usb",uptimeSeconds:$uptime}}' >> "$telemetry_contract"
done
telemetry_summary=$(Scripts/notchagent-desk-telemetry-evidence.sh "$telemetry_contract")
jq -e '.sampleCount == 2 and .firmwareVersion == "0.6.16"' <<<"$telemetry_summary" >/dev/null
jq -c '.telemetry.resetReason = "power_on"' "$telemetry_contract" > "$test_dir/power-on-telemetry.jsonl"
Scripts/notchagent-desk-telemetry-evidence.sh "$test_dir/power-on-telemetry.jsonl" power_on >/dev/null
if Scripts/notchagent-desk-telemetry-evidence.sh "$test_dir/power-on-telemetry.jsonl" usb >/dev/null 2>&1; then
    echo "FAIL: telemetry evidence accepted the wrong expected reset reason." >&2
    exit 1
fi
if Scripts/notchagent-desk-telemetry-evidence.sh "$telemetry_contract" panic >/dev/null 2>&1; then
    echo "FAIL: telemetry evidence accepted an unsupported expected reset reason." >&2
    exit 1
fi
jq -c '.telemetry.invalidFrameCount = 1' "$telemetry_contract" > "$test_dir/unhealthy-telemetry.jsonl"
if Scripts/notchagent-desk-telemetry-evidence.sh "$test_dir/unhealthy-telemetry.jsonl" >/dev/null 2>&1; then
    echo "FAIL: telemetry evidence accepted an invalid frame." >&2
    exit 1
fi

pilot_sources_ndjson="$test_dir/pilot-sources.ndjson"
for source_index in {0..34}; do
    source_report="$test_dir/pilot-day-${source_index}.jsonl"
    for elapsed in 4200 9200; do
        touch_count=$((elapsed == 4200 ? 1 : 2))
        jq -nc --arg marker "$source_index" --argjson elapsed "$elapsed" --argjson touchCount "$touch_count" '
          {marker:$marker,phase:"connected",elapsedMilliseconds:$elapsed,reliabilityFailures:[],
           firmwareVersion:"0.6.16",telemetry:{firmwareVersion:"0.6.16",framesPerSecond:7.4,
           minimumFreeHeapBytes:156596,invalidFrameCount:0,touchReadErrorCount:0,
           touchCount:$touchCount,touchControllerPresent:true,maximumTouchLatencyMs:25.343,
           resetReason:"usb"}}' >> "$source_report"
    done
    jq -nc --arg path "$source_report" \
      --arg sha "$(shasum -a 256 "$source_report" | awk '{print $1}')" \
      '{path:$path,sha:$sha}' >> "$pilot_sources_ndjson"
done
pilot_sources="$test_dir/pilot-sources.json"
jq -s . "$pilot_sources_ndjson" > "$pilot_sources"

consent_artifacts=(
  "$PWD/docs/img/panel-models.png"
  "$PWD/docs/img/settings.png"
  "$PWD/docs/img/desktop-burn.png"
  "$PWD/docs/img/panel-now.png"
  "$PWD/docs/img/dashboard-1.png"
)
consent_sources_ndjson="$test_dir/consent-sources.ndjson"
: > "$consent_sources_ndjson"
for participant_index in {1..5}; do
    participant_alias=$(printf 'P%02d' "$participant_index")
    consent_document="${consent_artifacts[$participant_index]}"
    consent_record="$test_dir/consent-${participant_alias}.json"
    Scripts/notchagent-desk-consent-evidence.sh "$consent_record" \
      "$participant_alias" "$consent_document" >/dev/null
    jq -nc --arg path "$consent_record" \
      --arg sha "$(shasum -a 256 "$consent_record" | awk '{print $1}')" \
      '{path:$path,sha:$sha}' >> "$consent_sources_ndjson"
done
consent_sources="$test_dir/consent-sources.json"
jq -s . "$consent_sources_ndjson" > "$consent_sources"

valid_pilot="$test_dir/valid-pilot.json"
jq -n --slurpfile sources "$pilot_sources" --slurpfile consents "$consent_sources" '
  def participant_alias($index): "P0\($index + 1)";
  def unit_alias($index): "DESK-B1-00\($index + 1)";
  def pilot_date($day):
    (("2026-09-01T00:00:00Z" | fromdateiso8601) + ($day * 86400) | strftime("%Y-%m-%d"));
  {schemaVersion:6, pilotAlias:"BETA1-A", severity1Defects:0,
   participants:[range(0; 5) as $participant |
     {participantAlias:participant_alias($participant),
      unitAlias:unit_alias($participant),
      macClass:(if $participant < 3 then "macbook-air-apple-silicon" else "macbook-pro-apple-silicon" end),
      macOSMajor:14,
      consentEvidenceFile:$consents[0][$participant].path,
      consentEvidenceSHA256:$consents[0][$participant].sha,
      days:[range(0; 7) as $day |
        {date:pilot_date($day), connectionSuccess:true, connectionSeconds:4.2,
         dockClass:(if $participant == 0 then "dock" elif $participant == 1 then "hub" else "direct" end),
         dockAlias:(if $participant == 0 then "DOCK-A" elif $participant == 1 then "HUB-B" else "DIRECT" end),
         firmwareVersion:"0.6.16", healthPass:true, resetAnomalyCount:0,
         minimumFreeHeapBytes:156596, minimumFramesPerSecond:7.4,
         maximumTouchLatencyMs:25.343, touchObserved:true,
         sourceReport:$sources[0][$participant * 7 + $day].path,
         sourceReportSHA256:$sources[0][$participant * 7 + $day].sha,
         updateResult:(if $participant < 4 and $day == 0 then "pass" else "not_attempted" end)}],
      usable:{touch:true,swipe:true,runner:true,alerts:true,recovery:($participant < 4)}}]}
' > "$valid_pilot"

Scripts/notchagent-desk-pilot-gate.sh "$valid_pilot" >/dev/null

tampered_consent="$test_dir/tampered-consent.json"
jq '.documentSHA256 = ("0" * 64)' "$test_dir/consent-P01.json" > "$tampered_consent"
tampered_consent_pilot="$test_dir/tampered-consent-pilot.json"
jq --arg evidence "$tampered_consent" \
  --arg sha "$(shasum -a 256 "$tampered_consent" | awk '{print $1}')" '
  .participants[0].consentEvidenceFile = $evidence |
  .participants[0].consentEvidenceSHA256 = $sha
' "$valid_pilot" > "$tampered_consent_pilot"
if Scripts/notchagent-desk-pilot-gate.sh "$tampered_consent_pilot" >/dev/null 2>&1; then
    echo "FAIL: pilot accepted a consent record with a fabricated document hash." >&2
    exit 1
fi

assert_pilot_rejected() {
    local expression="$1"
    local fixture="$test_dir/invalid-pilot.json"
    jq "$expression" "$valid_pilot" > "$fixture"
    if Scripts/notchagent-desk-pilot-gate.sh "$fixture" >/dev/null 2>&1; then
        echo "FAIL: pilot gate accepted invalid mutation: $expression" >&2
        exit 1
    fi
}

assert_pilot_rejected '.participants[0].days[6].date = "2026-09-09"'
assert_pilot_rejected '.participants[0].days[0].minimumFreeHeapBytes = 122879'
assert_pilot_rejected '.participants[0].days[0].minimumFramesPerSecond = 6.99'
assert_pilot_rejected '.participants[0].days[0].maximumTouchLatencyMs = 100.001'
assert_pilot_rejected '.participants[0].days[0].touchObserved = false'
assert_pilot_rejected '.participants[1].days[0].sourceReportSHA256 = .participants[0].days[0].sourceReportSHA256'
assert_pilot_rejected '.participants[0].email = "private@example.invalid"'
assert_pilot_rejected '.participants[0].notes = "free-form data is forbidden"'
assert_pilot_rejected '.participants[0].macOSMajor = 14.5'
assert_pilot_rejected '.participants[0].days[0].firmwareVersion = "0.6.1"'
assert_pilot_rejected '.participants[0].days[0].updateResult = "not_attempted"'
assert_pilot_rejected '.participants[0].consentEvidenceSHA256 = ("0" * 64)'
assert_pilot_rejected '.participants[1].consentEvidenceFile = .participants[0].consentEvidenceFile |
  .participants[1].consentEvidenceSHA256 = .participants[0].consentEvidenceSHA256'
assert_pilot_rejected '.participants[0].days |= (to_entries | map(
  .value.date = (("2026-09-08T00:00:00Z" | fromdateiso8601) + (.key * 86400) | strftime("%Y-%m-%d")) |
  .value))'

pilot_report="$test_dir/pilot-report.jsonl"
for elapsed in 4000 9000; do
  jq -nc --argjson elapsed "$elapsed" --argjson touchCount "$((elapsed == 4000 ? 2 : 3))" \
    '{phase:"connected",elapsedMilliseconds:$elapsed,reliabilityFailures:[],
    firmwareVersion:"0.6.16",telemetry:{firmwareVersion:"0.6.16",framesPerSecond:8.1,
    minimumFreeHeapBytes:160000,invalidFrameCount:0,touchReadErrorCount:0,
    touchCount:$touchCount,touchControllerPresent:true,
    maximumTouchLatencyMs:24.5,resetReason:"usb"}}' >> "$pilot_report"
done
pilot_day=$(Scripts/notchagent-desk-pilot-day.sh "$pilot_report" 2026-09-01 dock DOCK-A pass)
jq -e '.healthPass == true and .touchObserved == true and .connectionSeconds == 4 and
  .maximumTouchLatencyMs == 24.5 and .updateResult == "pass"' <<<"$pilot_day" >/dev/null
jq -c '.telemetry.touchCount = 0 | .telemetry.maximumTouchLatencyMs = 0' \
  "$pilot_report" > "$test_dir/pilot-no-touch.jsonl"
no_touch_day=$(Scripts/notchagent-desk-pilot-day.sh "$test_dir/pilot-no-touch.jsonl" \
  2026-09-01 direct DIRECT)
jq -e '.healthPass == false and .touchObserved == false' <<<"$no_touch_day" >/dev/null
jq -c '.telemetry.touchCount = 3' "$pilot_report" > "$test_dir/pilot-stale-touch.jsonl"
stale_touch_day=$(Scripts/notchagent-desk-pilot-day.sh "$test_dir/pilot-stale-touch.jsonl" \
  2026-09-01 direct DIRECT)
jq -e '.healthPass == false and .touchObserved == false' <<<"$stale_touch_day" >/dev/null
jq -c 'if .elapsedMilliseconds == 9000 then .phase = "searching" else . end' \
  "$pilot_report" > "$test_dir/pilot-disconnected.jsonl"
if Scripts/notchagent-desk-pilot-day.sh "$test_dir/pilot-disconnected.jsonl" \
    2026-09-01 direct DIRECT >/dev/null 2>&1; then
    echo "FAIL: pilot day accepted a connection discontinuity." >&2
    exit 1
fi
jq -c '.reliabilityFailures = ["touch_controller_unavailable"]' \
  "$pilot_report" > "$test_dir/pilot-unreliable.jsonl"
if Scripts/notchagent-desk-pilot-day.sh "$test_dir/pilot-unreliable.jsonl" \
    2026-09-01 direct DIRECT >/dev/null 2>&1; then
    echo "FAIL: pilot day accepted a reliability failure." >&2
    exit 1
fi
pilot_scaffold="$test_dir/pilot-scaffold.json"
Scripts/notchagent-desk-pilot-init.sh "$pilot_scaffold" 2026-09-01 >/dev/null
jq -e '.schemaVersion == 6 and (.participants | length) == 5 and
  all(.participants[]; (.days | length) == 7 and .consentEvidenceFile == null and
    .consentEvidenceSHA256 == null) and
  .participants[0].days[0].date == "2026-09-01" and
  .participants[0].days[6].date == "2026-09-07"' "$pilot_scaffold" >/dev/null
if Scripts/notchagent-desk-pilot-gate.sh "$pilot_scaffold" >/dev/null 2>&1; then
    echo "FAIL: untouched pilot scaffold was accepted." >&2
    exit 1
fi
if Scripts/notchagent-desk-pilot-init.sh "$pilot_scaffold" 2026-09-01 >/dev/null 2>&1; then
    echo "FAIL: pilot initializer overwrote an existing private file." >&2
    exit 1
fi

make_sample_report() {
    local item_id="$1"
    local supplier_alias="$2"
    local sku="$3"
    local checks="$4"
    local first_photo="$5"
    local second_photo="$6"
    local output="$7"
    jq -n --arg itemId "$item_id" --arg supplierAlias "$supplier_alias" --arg sku "$sku" \
      --argjson checks "$checks" --arg firstPhotoFile "$first_photo" --arg secondPhotoFile "$second_photo" \
      --arg firstPhoto "$(shasum -a 256 "$first_photo" | awk '{print $1}')" \
      --arg secondPhoto "$(shasum -a 256 "$second_photo" | awk '{print $1}')" '
      {schemaVersion:2,itemId:$itemId,supplierAlias:$supplierAlias,sku:$sku,
       inspectedAt:"2026-08-13T15:00:00Z",inspectorAlias:"OPERATOR-A",
       photoFiles:[$firstPhotoFile,$secondPhotoFile],
       photoSHA256s:[$firstPhoto,$secondPhoto],checks:$checks,result:"pass"}
    ' > "$output"
}

display_sample="$test_dir/display-sample.json"
cable_sample="$test_dir/cable-sample.json"
enclosure_sample="$test_dir/enclosure-sample.json"
packaging_sample="$test_dir/packaging-sample.json"
make_sample_report display SUPPLIER-DISPLAY SKU-DISPLAY \
  '{"display":true,"noDeadPixels":true,"touch":true}' \
  "$PWD/docs/img/notch-compact.png" "$PWD/docs/img/dashboard-2.png" "$display_sample"
make_sample_report data-cable SUPPLIER-DATA-CABLE SKU-DATA-CABLE \
  '{"dataTransfer":true,"directMac":true,"dock":true}' \
  "$PWD/docs/img/alert-almost-empty.png" "$PWD/docs/img/dashboard-1.png" "$cable_sample"
make_sample_report enclosure SUPPLIER-ENCLOSURE SKU-ENCLOSURE \
  '{"bootAccess":true,"connectorFit":true,"touchAccess":true,"ventilation":true}' \
  "$PWD/docs/img/panel-now.png" "$PWD/docs/img/panel-rhythm.png" "$enclosure_sample"
make_sample_report packaging SUPPLIER-PACKAGING SKU-PACKAGING \
  '{"onboardingQR":true,"recoveryCard":true}' \
  "$PWD/docs/img/panel-burn.png" "$PWD/docs/img/desktop-now.png" "$packaging_sample"

valid_bom="$test_dir/valid-bom.json"
jq --arg displayFile "$display_sample" --arg displaySHA "$(shasum -a 256 "$display_sample" | awk '{print $1}')" \
  --arg cableFile "$cable_sample" --arg cableSHA "$(shasum -a 256 "$cable_sample" | awk '{print $1}')" \
  --arg enclosureFile "$enclosure_sample" --arg enclosureSHA "$(shasum -a 256 "$enclosure_sample" | awk '{print $1}')" \
  --arg packagingFile "$packaging_sample" --arg packagingSHA "$(shasum -a 256 "$packaging_sample" | awk '{print $1}')" '
  .schemaVersion = 4 |
  .items |= map(
    .supplierAlias = ("SUPPLIER-" + (.id | ascii_upcase)) |
    .sku = ("SKU-" + (.id | ascii_upcase)) |
    .unitCost = 100 |
    .minimumOrder = 1 |
    .orderQuantity = 5 |
    .leadTimeDays = 7 |
    .samplePassed = true |
    .sampleEvidenceFile = (if .id == "display" then $displayFile
      elif .id == "data-cable" then $cableFile
      elif .id == "enclosure" then $enclosureFile else $packagingFile end) |
    .sampleEvidenceSHA256 = (if .id == "display" then $displaySHA
      elif .id == "data-cable" then $cableSHA
      elif .id == "enclosure" then $enclosureSHA else $packagingSHA end) |
    if .id == "data-cable" then
      .dataTransferPassed = true | .directMacPassed = true | .dockPassed = true
    elif .id == "enclosure" then
      .connectorFitPassed = true | .touchAccessPassed = true |
      .ventilationPassed = true | .bootAccessPassed = true
    elif .id == "packaging" then
      .onboardingQRIncluded = true | .recoveryCardIncluded = true
    else . end
  )
' docs/NOTCHAGENT_DESK_PROCUREMENT_TEMPLATE.json > "$valid_bom"

Scripts/notchagent-desk-procurement-gate.sh "$valid_bom" >/dev/null

invalid_photo_sample="$test_dir/invalid-photo-sample.json"
jq '.photoSHA256s[0] = ("0" * 64)' "$display_sample" > "$invalid_photo_sample"
invalid_photo_bom="$test_dir/invalid-photo-bom.json"
jq --arg evidence "$invalid_photo_sample" \
  --arg sha "$(shasum -a 256 "$invalid_photo_sample" | awk '{print $1}')" '
  (.items[] | select(.id == "display")) |=
    (.sampleEvidenceFile = $evidence | .sampleEvidenceSHA256 = $sha)
' "$valid_bom" > "$invalid_photo_bom"
if Scripts/notchagent-desk-procurement-gate.sh "$invalid_photo_bom" >/dev/null 2>&1; then
    echo "FAIL: procurement accepted an inspection photo with a fabricated hash." >&2
    exit 1
fi

assert_bom_rejected() {
    local expression="$1"
    local fixture="$test_dir/invalid-bom.json"
    jq "$expression" "$valid_bom" > "$fixture"
    if Scripts/notchagent-desk-procurement-gate.sh "$fixture" >/dev/null 2>&1; then
        echo "FAIL: procurement gate accepted invalid mutation: $expression" >&2
        exit 1
    fi
}

assert_bom_rejected '.plannedUnits = 5.5'
assert_bom_rejected '.items[0].sku = "   "'
assert_bom_rejected '.items[0].minimumOrder = 1.5'
assert_bom_rejected '.items[0].orderQuantity = 4'
assert_bom_rejected '.items[0].minimumOrder = 3 | .items[0].orderQuantity = 5'
assert_bom_rejected '.items[0].orderQuantity = 5.5'
assert_bom_rejected '.items[0].customer = "private data"'
assert_bom_rejected '.items[1].sampleEvidenceFile = .items[0].sampleEvidenceFile |
  .items[1].sampleEvidenceSHA256 = .items[0].sampleEvidenceSHA256'
assert_bom_rejected '.items[0].sampleEvidenceSHA256 = ("0" * 64)'

valid_matrix="$test_dir/valid-matrix.json"
matrix_entries="$test_dir/matrix-entries.jsonl"
: > "$matrix_entries"
matrix_counter=0
for mac_index in 1 2; do
    if [[ "$mac_index" == 1 ]]; then
        matrix_mac="macbook-air-apple-silicon"
        matrix_unit="DESK-B1-001"
    else
        matrix_mac="macbook-pro-apple-silicon"
        matrix_unit="DESK-B1-002"
    fi
    for matrix_connection in direct dock hub; do
        matrix_counter=$((matrix_counter + 1))
        matrix_stamp=$(printf '20260813T1500%02dZ' "$matrix_counter")
        matrix_report="$test_dir/reconnect-$matrix_stamp.json"
        jq -n --arg marker "MATRIX-$matrix_counter" \
          '[range(1; 11) as $cycle | {marker:$marker,cycle:$cycle,reconnectMilliseconds:8200,
            resetMilliseconds:2500,telemetryMilliseconds:5700,
            telemetry:{firmwareVersion:"0.6.16",framesPerSecond:8.2,minimumFreeHeapBytes:160000,
              invalidFrameCount:0,touchReadErrorCount:0,touchControllerPresent:true,
              touchPollAttemptCount:180,uptimeSeconds:2,handshakeCount:1,resetReason:"usb"}}]' > "$matrix_report"
        if [[ "$matrix_connection" == direct ]]; then
            matrix_alias="DIRECT"
        elif [[ "$matrix_connection" == dock ]]; then
            matrix_alias="DOCK-A"
        else
            matrix_alias="HUB-A"
        fi
        NOTCHAGENT_DESK_MATRIX_MACOS_MAJOR=14 Scripts/notchagent-desk-matrix-entry.sh \
          "$matrix_report" "$matrix_mac" "$matrix_unit" "$matrix_connection" "$matrix_alias" \
          >> "$matrix_entries"
    done
done
jq -s '{schemaVersion:3,matrixAlias:"BETA1-MATRIX-A",entries:.}' \
  "$matrix_entries" > "$valid_matrix"

Scripts/notchagent-desk-matrix-gate.sh "$valid_matrix" >/dev/null

matrix_raw="$test_dir/reconnect-20260813T150002Z.json"
matrix_entry=$(NOTCHAGENT_DESK_MATRIX_MACOS_MAJOR=14 Scripts/notchagent-desk-matrix-entry.sh \
  "$matrix_raw" macbook-air-apple-silicon DESK-B1-001 dock DOCK-A)
jq -e '.attempts == 10 and .successes == 10 and .maximumConnectionSeconds == 8.2 and
  .connectionClass == "dock" and .connectionAlias == "DOCK-A" and
  .maximumInvalidFrameCount == 0 and
  (.sourceReport | endswith("reconnect-20260813T150002Z.json")) and
  (.sourceReportSHA256 | test("^[0-9a-f]{64}$"))' <<<"$matrix_entry" >/dev/null
if NOTCHAGENT_DESK_MATRIX_MACOS_MAJOR=14 Scripts/notchagent-desk-matrix-entry.sh \
  "$matrix_raw" macbook-air-apple-silicon DESK-B1-001 direct DOCK-A >/dev/null 2>&1; then
    echo "FAIL: matrix entry accepted a non-DIRECT alias for direct USB." >&2
    exit 1
fi

assert_matrix_rejected() {
    local expression="$1"
    local fixture="$test_dir/invalid-matrix.json"
    jq "$expression" "$valid_matrix" > "$fixture"
    if Scripts/notchagent-desk-matrix-gate.sh "$fixture" >/dev/null 2>&1; then
        echo "FAIL: matrix gate accepted invalid mutation: $expression" >&2
        exit 1
    fi
}

assert_matrix_rejected 'del(.entries[] | select(.connectionClass == "hub"))'
assert_matrix_rejected '.entries[0].successes = 9'
assert_matrix_rejected '.entries[0].maximumConnectionSeconds = 15.001'
assert_matrix_rejected '.entries[0].hostname = "private-host"'
assert_matrix_rejected '.entries[0].firmwareVersion = "0.6.1"'
assert_matrix_rejected '.entries[1].sourceReportSHA256 = .entries[0].sourceReportSHA256'
assert_matrix_rejected '.entries[0].firmwareImageSHA256 = ("f" * 64)'
assert_matrix_rejected '.entries[0].minimumFramesPerSecond = 7.9'
assert_matrix_rejected '.entries[0].sourceReport = .entries[1].sourceReport'

factory_a="$test_dir/factory-a.json"
factory_b="$test_dir/factory-b.json"
factory_manifest_sha=$(shasum -a 256 firmware/notchagent_desk/release/manifest.json | awk '{print $1}')
factory_visual_helper_fixture="$test_dir/factory-visual-helper.json"
Scripts/notchagent-desk-factory-visual-evidence.sh "$factory_visual_helper_fixture" \
  BETA1-LOT-A DESK-B1-099 "$PWD/docs/img/notch-compact.png" \
  "$PWD/docs/img/dashboard-2.png" "$PWD/docs/img/alert-almost-empty.png" \
  "$PWD/docs/img/dashboard-1.png" >/dev/null
Scripts/notchagent-desk-factory-visual-gate.sh "$factory_visual_helper_fixture" \
  BETA1-LOT-A DESK-B1-099 >/dev/null
if Scripts/notchagent-desk-factory-visual-evidence.sh "$factory_visual_helper_fixture" \
  BETA1-LOT-A DESK-B1-099 "$PWD/docs/img/notch-compact.png" \
  "$PWD/docs/img/dashboard-2.png" "$PWD/docs/img/alert-almost-empty.png" \
  "$PWD/docs/img/dashboard-1.png" >/dev/null 2>&1; then
    echo "FAIL: factory visual helper overwrote existing private evidence." >&2
    exit 1
fi
make_factory_visual() {
    local index="$1"
    local unit_alias="$2"
    local output="$3"
    local artifacts='{}'
    local check offset size artifact sha
    offset=0
    for check in display touch swipe runner; do
        offset=$((offset + 1))
        size=$((48 + index * 8 + offset))
        artifact="$test_dir/factory-visual-${index}-${check}.png"
        sips -z "$size" "$size" docs/img/notch-compact.png --out "$artifact" >/dev/null
        sha=$(shasum -a 256 "$artifact" | awk '{print $1}')
        artifacts=$(jq -nc --argjson current "$artifacts" --arg check "$check" \
          --arg file "$artifact" --arg sha "$sha" '$current + {($check):{file:$file,sha256:$sha}}')
    done
    jq -n --arg unitAlias "$unit_alias" --argjson artifacts "$artifacts" '
      {schemaVersion:1,lotAlias:"BETA1-LOT-A",unitAlias:$unitAlias,
       capturedAt:"2026-08-13T14:00:00Z",artifacts:$artifacts,result:"pass"}
    ' > "$output"
}
factory_visuals=()
for visual_index in 1 2 3 4 5; do
    visual_evidence="$test_dir/factory-visual-${visual_index}.json"
    make_factory_visual "$visual_index" "DESK-B1-00${visual_index}" "$visual_evidence"
    factory_visuals+=("$visual_evidence")
done
make_factory_telemetry() {
    local output="$1"
    local marker="$2"
    for elapsed in 1000 6000; do
        jq -nc --arg marker "$marker" --argjson elapsed "$elapsed" \
          '{marker:$marker,elapsedMilliseconds:$elapsed,telemetry:{firmwareVersion:"0.6.16",
            framesPerSecond:8.2,minimumFreeHeapBytes:160000,invalidFrameCount:0,
            touchReadErrorCount:0,touchControllerPresent:true,resetReason:"usb"}}' >> "$output"
    done
}
factory_telemetry_a="$test_dir/factory-telemetry-a.jsonl"
factory_telemetry_b="$test_dir/factory-telemetry-b.jsonl"
make_factory_telemetry "$factory_telemetry_a" A
make_factory_telemetry "$factory_telemetry_b" B
factory_telemetry_a_sha=$(shasum -a 256 "$factory_telemetry_a" | awk '{print $1}')
factory_telemetry_b_sha=$(shasum -a 256 "$factory_telemetry_b" | awk '{print $1}')
factory_telemetry_summary=$(Scripts/notchagent-desk-telemetry-evidence.sh "$factory_telemetry_a")
jq -n --arg packageManifestSHA256 "$factory_manifest_sha" \
  --arg telemetryReport "$factory_telemetry_a" --arg telemetrySHA256 "$factory_telemetry_a_sha" \
  --arg visualEvidenceFile "${factory_visuals[1]}" \
  --arg visualEvidenceSHA256 "$(shasum -a 256 "${factory_visuals[1]}" | awk '{print $1}')" \
  --argjson telemetry "$factory_telemetry_summary" '{schemaVersion:7,
  lotAlias:"BETA1-LOT-A",unitAlias:"DESK-B1-001",
  startedAt:"2026-08-13T14:00:00Z", completedAt:"2026-08-13T14:01:00Z",
  firmwareVersion:"0.6.16", flashVerified:true, usbReenumerated:true,
  telemetryHealthy:true, checks:{display:"pass",touch:"pass",swipe:"pass",runner:"pass"},
  packageManifestSHA256:$packageManifestSHA256,
  visualEvidenceFile:$visualEvidenceFile,visualEvidenceSHA256:$visualEvidenceSHA256,
  telemetryReport:$telemetryReport,telemetrySHA256:$telemetrySHA256,telemetry:$telemetry,
  result:"accepted"}' > "$factory_a"
jq --arg report "$factory_telemetry_b" --arg sha "$factory_telemetry_b_sha" \
  --arg visual "${factory_visuals[2]}" \
  --arg visualSHA "$(shasum -a 256 "${factory_visuals[2]}" | awk '{print $1}')" \
  '.unitAlias = "DESK-B1-002" | .telemetryReport = $report | .telemetrySHA256 = $sha |
   .visualEvidenceFile = $visual | .visualEvidenceSHA256 = $visualSHA' \
  "$factory_a" > "$factory_b"
NOTCHAGENT_DESK_LOT_ALIAS=BETA1-LOT-A NOTCHAGENT_DESK_FACTORY_MIN_UNITS=2 \
    Scripts/notchagent-desk-factory-report-gate.sh "$factory_a" "$factory_b" >/dev/null

factory_reports=("$factory_a" "$factory_b")
for index in 3 4 5; do
    fixture="$test_dir/factory-${index}.json"
    telemetry_fixture="$test_dir/factory-telemetry-${index}.jsonl"
    make_factory_telemetry "$telemetry_fixture" "$index"
    telemetry_fixture_sha=$(shasum -a 256 "$telemetry_fixture" | awk '{print $1}')
    jq --arg alias "DESK-B1-00${index}" --arg report "$telemetry_fixture" \
      --arg sha "$telemetry_fixture_sha" --arg visual "${factory_visuals[$index]}" \
      --arg visualSHA "$(shasum -a 256 "${factory_visuals[$index]}" | awk '{print $1}')" \
      '.unitAlias = $alias | .telemetryReport = $report | .telemetrySHA256 = $sha |
       .visualEvidenceFile = $visual | .visualEvidenceSHA256 = $visualSHA' \
      "$factory_a" > "$fixture"
    factory_reports+=("$fixture")
done
commercial_evidence=$(Scripts/notchagent-desk-commercial-lot-gate.sh \
    "$valid_bom" "${factory_reports[@]}")
jq -e '.gate == "commercial-lot-freeze" and .plannedUnits == 5 and
  .schemaVersion == 2 and .acceptedUnits == 5 and
  (.factoryReportFiles | length) == 5 and
  (.factoryReportSHA256s | length) == 5 and
  (.procurementFile | length) > 0' \
  <<<"$commercial_evidence" >/dev/null
commercial_evidence_file="$test_dir/commercial-evidence.json"
print -r -- "$commercial_evidence" > "$commercial_evidence_file"
commercial_status="$test_dir/commercial-status.json"
jq --arg evidence "$commercial_evidence_file" '
  (.gates[] | select(.id == "bom-enclosure-cable-freeze")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$commercial_status"
set +e
commercial_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$commercial_status" \
  Scripts/notchagent-desk-beta1-gate.sh 2>&1)
commercial_result=$?
set -e
[[ $commercial_result -eq 1 && "$commercial_output" == "NOT READY:"* ]] || {
    echo "FAIL: recomputable commercial evidence was not accepted by the Beta gate: $commercial_output" >&2
    exit 1
}
commercial_tampered="$test_dir/commercial-tampered.json"
jq '.lotAlias = "BETA1-LOT-B"' "$commercial_evidence_file" > "$commercial_tampered"
jq --arg evidence "$commercial_tampered" '
  (.gates[] | select(.id == "bom-enclosure-cable-freeze")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$commercial_status"
set +e
commercial_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$commercial_status" \
  Scripts/notchagent-desk-beta1-gate.sh 2>&1)
commercial_result=$?
set -e
[[ $commercial_result -eq 1 && "$commercial_output" == "INVALID:"* ]] || {
    echo "FAIL: Beta gate accepted a commercial summary that differs from its sources." >&2
    exit 1
}
if Scripts/notchagent-desk-commercial-lot-gate.sh \
    "$valid_bom" "$factory_a" "$factory_b" >/dev/null 2>&1; then
    echo "FAIL: commercial lot gate accepted fewer QC reports than planned units." >&2
    exit 1
fi

soak_source="$test_dir/soak-source.jsonl"
for elapsed in 0 10000 20000; do
    captured_at=$(printf '2026-08-13T14:00:%02dZ' "$((elapsed / 1000))")
    jq -nc --argjson elapsed "$elapsed" --arg capturedAt "$captured_at" \
      '{phase:"connected",protocolMajor:1,protocolMinor:1,firmwareVersion:"0.6.16",
        capturedAt:$capturedAt,elapsedMilliseconds:$elapsed,reliabilityFailures:[],telemetry:{firmwareVersion:"0.6.16",
        framesPerSecond:8.2,minimumFreeHeapBytes:160000,invalidFrameCount:0,
        touchReadErrorCount:0,touchControllerPresent:true}}' >> "$soak_source"
done
soak_app="$test_dir/NotchAgent.app"
mkdir -p "$soak_app/Contents"
plutil -create xml1 "$soak_app/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 3.1.1 "$soak_app/Contents/Info.plist"
plutil -insert CFBundleVersion -string 4 "$soak_app/Contents/Info.plist"
soak_evidence=$(NOTCHAGENT_DESK_SOAK_APP="$soak_app" \
  Scripts/notchagent-desk-soak-evidence.sh "$soak_source" 20)
jq -e --arg source "$soak_source" '
  .schemaVersion == 4 and .gate == "app-desk-soak" and .durationSeconds == 20 and
  .samples == 3 and .wallClockDurationSeconds == 20 and
  .maximumWallClockGapSeconds == 10 and .sourceReport == $source and .result == "pass"
' <<<"$soak_evidence" >/dev/null
unhealthy_soak="$test_dir/unhealthy-soak.jsonl"
jq -c 'if .elapsedMilliseconds == 10000 then .telemetry.invalidFrameCount = 1 else . end' \
  "$soak_source" > "$unhealthy_soak"
if NOTCHAGENT_DESK_SOAK_APP="$soak_app" \
  Scripts/notchagent-desk-soak-evidence.sh "$unhealthy_soak" 20 >/dev/null 2>&1; then
    echo "FAIL: soak evidence accepted an invalid display frame." >&2
    exit 1
fi
gapped_soak="$test_dir/gapped-soak.jsonl"
jq -c 'if .elapsedMilliseconds == 10000 then
  .elapsedMilliseconds = 16001 | .capturedAt = "2026-08-13T14:00:16Z" else . end' \
  "$soak_source" > "$gapped_soak"
if NOTCHAGENT_DESK_SOAK_APP="$soak_app" \
  Scripts/notchagent-desk-soak-evidence.sh "$gapped_soak" 20 >/dev/null 2>&1; then
    echo "FAIL: soak evidence accepted a sample gap above 16 seconds." >&2
    exit 1
fi
rollback_soak="$test_dir/rollback-soak.jsonl"
jq -c 'if .elapsedMilliseconds == 10000 then
  .capturedAt = "2026-08-13T13:59:59Z" else . end' "$soak_source" > "$rollback_soak"
if NOTCHAGENT_DESK_SOAK_APP="$soak_app" \
  Scripts/notchagent-desk-soak-evidence.sh "$rollback_soak" 20 >/dev/null 2>&1; then
    echo "FAIL: soak evidence accepted a UTC clock rollback." >&2
    exit 1
fi

assert_factory_rejected() {
    local expression="$1"
    local fixture="$test_dir/invalid-factory.json"
    jq "$expression" "$factory_a" > "$fixture"
    if NOTCHAGENT_DESK_LOT_ALIAS=BETA1-LOT-A \
        Scripts/notchagent-desk-factory-report-gate.sh "$fixture" >/dev/null 2>&1; then
        echo "FAIL: factory report gate accepted invalid mutation: $expression" >&2
        exit 1
    fi
}

assert_factory_rejected '.firmwareVersion = "0.6.1"'
assert_factory_rejected '.checks.swipe = "pending"'
assert_factory_rejected '.telemetry.minimumFramesPerSecond = 6.9'
assert_factory_rejected '.packageManifestSHA256 = ("d" * 64)'
assert_factory_rejected '.lotAlias = "BETA1-LOT-B"'
assert_factory_rejected '.serialNumber = "private-serial"'
old_factory_visual="$test_dir/old-factory-visual.json"
jq '.capturedAt = "2026-08-13T12:59:59Z"' "${factory_visuals[1]}" > "$old_factory_visual"
old_factory_visual_report="$test_dir/old-factory-visual-report.json"
jq --arg visual "$old_factory_visual" \
  --arg sha "$(shasum -a 256 "$old_factory_visual" | awk '{print $1}')" '
  .visualEvidenceFile = $visual | .visualEvidenceSHA256 = $sha
' "$factory_a" > "$old_factory_visual_report"
if NOTCHAGENT_DESK_LOT_ALIAS=BETA1-LOT-A \
    Scripts/notchagent-desk-factory-report-gate.sh "$old_factory_visual_report" >/dev/null 2>&1; then
    echo "FAIL: factory gate accepted visual evidence outside the unit QC window." >&2
    exit 1
fi
if NOTCHAGENT_DESK_LOT_ALIAS=BETA1-LOT-A NOTCHAGENT_DESK_FACTORY_MIN_UNITS=2 \
    Scripts/notchagent-desk-factory-report-gate.sh "$factory_a" "$factory_a" >/dev/null 2>&1; then
    echo "FAIL: factory report gate accepted a repeated unit alias." >&2
    exit 1
fi
factory_reused="$test_dir/factory-reused.json"
jq '.unitAlias = "DESK-B1-002"' "$factory_a" > "$factory_reused"
if NOTCHAGENT_DESK_LOT_ALIAS=BETA1-LOT-A NOTCHAGENT_DESK_FACTORY_MIN_UNITS=2 \
    Scripts/notchagent-desk-factory-report-gate.sh "$factory_a" \
    "$factory_reused" >/dev/null 2>&1; then
    echo "FAIL: factory report gate accepted reused telemetry evidence." >&2
    exit 1
fi

set +e
beta_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$status_fixture" \
  Scripts/notchagent-desk-beta1-gate.sh 2>&1)
beta_result=$?
set -e
[[ $beta_result -eq 1 && "$beta_output" == "NOT READY:"* ]] || {
    echo "FAIL: current Beta 1 status should be structurally valid with open gates." >&2
    exit 1
}
beta_operational_status=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$status_fixture" \
  Scripts/notchagent-desk-beta1-status.sh)
jq -e '
  .schemaVersion == 1 and
  ([.counts.pass,.counts.waived,.counts.pending,.counts.fail] | add) == 16 and
  (.openGates | length) == (.counts.pending + .counts.fail) and
  all(.openGates[];
    (.category == "physical_action" or .category == "external_gate" or
     .category == "implementation" or .category == "in_progress")) and
  ([.openGates[].category] | index("external_gate")) != null and
  ([.openGates[] | select(.id == "soak-24-hours") | .category] |
    all(. == "in_progress" or . == "implementation"))
' <<<"$beta_operational_status" >/dev/null || {
    echo "FAIL: operational Beta status does not classify open gates." >&2
    exit 1
}

assert_beta_status_invalid() {
    local expression="$1"
    local fixture="$test_dir/invalid-beta-status.json"
    jq "$expression" $status_fixture > "$fixture"
    set +e
    local output
    output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$fixture" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
    local result=$?
    set -e
    if [[ $result -eq 0 || "$output" != "INVALID:"* ]]; then
        echo "FAIL: Beta 1 gate did not fail closed for mutation: $expression" >&2
        exit 1
    fi
}

assert_beta_status_invalid 'del(.gates[] | select(.id == "soak-24-hours"))'
assert_beta_status_invalid '.gates[0].status = "approved"'
assert_beta_status_invalid '(.gates[] | select(.id == "soak-24-hours")) |= (.status = "pass" | .evidence = "/missing/soak.json")'
assert_beta_status_invalid '(.gates[] | select(.id == "soak-24-hours")) |= (.status = "waived" | .evidence = "/missing/waiver.json")'
assert_beta_status_invalid '(.gates[] | select(.id == "physical-touch-latency")) |= (.status = "waived" | .evidence = "/missing/touch-waiver.json")'
assert_beta_status_invalid '(.gates[] | select(.id == "abrupt-power-recovery")) |= (.status = "waived" | .evidence = "/missing/power-waiver.json")'
assert_beta_status_invalid '(.gates[] | select(.id == "bom-enclosure-cable-freeze")) |= (.status = "waived" | .evidence = "/missing/bom-waiver.json")'
assert_beta_status_invalid '(.gates[] | select(.id == "five-user-seven-day-pilot")) |= (.status = "waived" | .evidence = "unsupported")'
beta_status_link="$test_dir/beta-status-link.json"
ln -s "$PWD/$status_fixture" "$beta_status_link"
if NOTCHAGENT_DESK_BETA1_STATUS_FILE="$beta_status_link" \
    Scripts/notchagent-desk-beta1-gate.sh >/dev/null 2>&1; then
    echo "FAIL: Beta gate accepted a symbolic-link status contract." >&2
    exit 1
fi

touch_source="$test_dir/touch-source.jsonl"
print -r -- '{"capturedAt":"2026-08-13T17:40:00Z","firmwareVersion":"0.6.16",
  "protocolMajor":1,"protocolMinor":1,"reliabilityFailures":[],"telemetry":{
  "firmwareVersion":"0.6.16","touchControllerPresent":true,"touchCount":8,
  "touchInterruptCount":8,"touchPollTouchCount":0,"touchReadErrorCount":0,
  "maximumTouchLatencyMs":5.39}}' > "$touch_source"
valid_touch="$test_dir/valid-touch.json"
Scripts/notchagent-desk-touch-summary.sh "$touch_source" pass pass pass pass > "$valid_touch"
touch_status="$test_dir/touch-status.json"
jq --arg evidence "$valid_touch" '
  (.gates[] | select(.id == "physical-touch-latency")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$touch_status"
set +e
touch_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$touch_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
touch_result=$?
set -e
[[ $touch_result -eq 1 && "$touch_output" == "NOT READY:"* ]] || {
    echo "FAIL: healthy touch with all physical interactions was not accepted." >&2
    exit 1
}
jq '.physicalChecks.swipeLeft = "pending"' "$valid_touch" > "$test_dir/incomplete-touch.json"
jq --arg evidence "$test_dir/incomplete-touch.json" '
  (.gates[] | select(.id == "physical-touch-latency")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$touch_status"
set +e
touch_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$touch_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
touch_result=$?
set -e
[[ $touch_result -eq 1 && "$touch_output" == "INVALID:"* ]] || {
    echo "FAIL: touch gate accepted an unverified swipe." >&2
    exit 1
}

current_smoke="$test_dir/current-smoke.json"
current_smoke_source="$test_dir/current-smoke-source.jsonl"
for sample_index in {0..9}; do
    elapsed=$((sample_index * 5000))
    jq -nc --argjson elapsed "$elapsed" '
      {capturedAt:"2026-08-13T17:40:45Z",elapsedMilliseconds:$elapsed,
       phase:"connected",protocolMajor:1,protocolMinor:1,firmwareVersion:"0.6.16",
       reliabilityFailures:[],telemetry:{firmwareVersion:"0.6.16",framesPerSecond:8.2,
       minimumFreeHeapBytes:160000,invalidFrameCount:0,touchReadErrorCount:0,
       touchControllerPresent:true,touchCount:0}}
    ' >> "$current_smoke_source"
done
current_smoke_sha=$(shasum -a 256 "$current_smoke_source" | awk '{print $1}')
jq -n --slurpfile package firmware/notchagent_desk/release/manifest.json \
  --arg source "$current_smoke_source" --arg reportSHA "$current_smoke_sha" '
  {schemaVersion:2,gate:"final-app-physical-smoke",result:"pass",
   capturedAt:"2026-08-13T17:40:45Z",durationSeconds:45,
   appVersion:"3.1.1",buildNumber:"4",signatureKind:"Apple Development",
   firmwareVersion:"0.6.16",firmwareImageSHA256:$package[0].imageSHA256,
   firmwareSourceSHA256:$package[0].sourceSHA256,protocolVersion:"1.1",
   connectionContinuity:true,firstConnectionMilliseconds:0,
   maximumSampleGapMilliseconds:5000,minimumFramesPerSecond:8.2,
   minimumFreeHeapBytes:160000,maximumInvalidFrameCount:0,
   maximumTouchReadErrorCount:0,touchControllerPresent:true,touchCount:0,
   sourceReport:$source,reportSHA256:$reportSHA}
' > "$current_smoke"
current_reconnect="$test_dir/current-reconnect.json"
current_reconnect_source="$test_dir/reconnect-20260813T174200Z.json"
jq -n '[range(1; 101) as $cycle |
  {cycle:$cycle,resetMilliseconds:120,telemetryMilliseconds:380,reconnectMilliseconds:500,
   telemetry:{firmwareVersion:"0.6.16",framesPerSecond:8.2,minimumFreeHeapBytes:160000,
    invalidFrameCount:0,touchReadErrorCount:0,touchControllerPresent:true,
    touchPollAttemptCount:20,uptimeSeconds:2,handshakeCount:1,resetReason:"usb"}}]' > "$current_reconnect_source"
Scripts/notchagent-desk-reconnect-evidence.sh "$current_reconnect_source" 100 > "$current_reconnect"

invalid_smoke="$test_dir/invalid-smoke.json"
jq '.maximumSampleGapMilliseconds = 10001' "$current_smoke" > "$invalid_smoke"
invalid_smoke_status="$test_dir/invalid-smoke-status.json"
jq --arg evidence "$invalid_smoke" '
  (.gates[] | select(.id == "automatic-discovery")) |= (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$invalid_smoke_status"
set +e
invalid_smoke_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$invalid_smoke_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
invalid_smoke_result=$?
set -e
[[ $invalid_smoke_result -eq 1 && "$invalid_smoke_output" == "INVALID:"* ]] || {
    echo "FAIL: automatic discovery accepted a telemetry gap above 10 seconds." >&2
    exit 1
}

invalid_telemetry="$test_dir/invalid-smoke-telemetry.json"
jq '.minimumFramesPerSecond = 6.9' "$current_smoke" > "$invalid_telemetry"
invalid_telemetry_status="$test_dir/invalid-smoke-telemetry-status.json"
jq --arg evidence "$invalid_telemetry" '
  (.gates[] | select(.id == "hardware-telemetry")) |= (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$invalid_telemetry_status"
set +e
invalid_telemetry_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$invalid_telemetry_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
invalid_telemetry_result=$?
set -e
[[ $invalid_telemetry_result -eq 1 && "$invalid_telemetry_output" == "INVALID:"* ]] || {
    echo "FAIL: hardware telemetry accepted FPS below the release threshold." >&2
    exit 1
}

invalid_smoke_firmware="$test_dir/invalid-smoke-firmware.json"
jq '.firmwareSourceSHA256 = ("f" * 64)' "$current_smoke" > "$invalid_smoke_firmware"
invalid_smoke_firmware_status="$test_dir/invalid-smoke-firmware-status.json"
jq --arg evidence "$invalid_smoke_firmware" '
  (.gates[] | select(.id == "automatic-discovery")) |= (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$invalid_smoke_firmware_status"
set +e
invalid_smoke_firmware_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$invalid_smoke_firmware_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
invalid_smoke_firmware_result=$?
set -e
[[ $invalid_smoke_firmware_result -eq 1 && "$invalid_smoke_firmware_output" == "INVALID:"* ]] || {
    echo "FAIL: automatic discovery accepted evidence from different firmware source." >&2
    exit 1
}

invalid_reconnect="$test_dir/invalid-reconnect-image.json"
jq '.firmwareImageSHA256 = ("f" * 64)' "$current_reconnect" > "$invalid_reconnect"
invalid_reconnect_status="$test_dir/invalid-reconnect-status.json"
jq --arg evidence "$invalid_reconnect" '
  (.gates[] | select(.id == "physical-reconnect-100")) |= (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$invalid_reconnect_status"
set +e
invalid_reconnect_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$invalid_reconnect_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
invalid_reconnect_result=$?
set -e
[[ $invalid_reconnect_result -eq 1 && "$invalid_reconnect_output" == "INVALID:"* ]] || {
    echo "FAIL: physical reconnect accepted evidence from a different firmware image." >&2
    exit 1
}

valid_onboarding="$test_dir/valid-onboarding.json"
qr_sha=$(shasum -a 256 docs/img/notchagent-desk-onboarding-qr.svg | awk '{print $1}')
jq -n --arg qrSHA256 "$qr_sha" '{schemaVersion:3,gate:"onboarding-qr",result:"pass",
  verifiedAt:"2026-08-13T14:00:00Z",
  verificationMethod:"live-download",
  url:"https://github.com/luisroquette/notchagent/blob/master/docs/NOTCHAGENT_DESK_ONBOARDING.md",
  qrFile:"docs/img/notchagent-desk-onboarding-qr.svg",qrSHA256:$qrSHA256,
  publishedCommitSHA:("a" * 40),guideHTTPStatus:200,guideContentSHA256:("b" * 64),
  releaseAssetURL:"https://github.com/luisroquette/notchagent/releases/download/v3.1.1/NotchAgent-Desk-Beta1-3.1.1.zip",
  releaseAssetSHA256:("c" * 64),notarizationEvidenceSHA256:("d" * 64),
  downloadedExecutableSHA256:("a" * 64),downloadedFirmwareManifestSHA256:("e" * 64),
  artifactSignatureVerified:true,artifactStapleValidated:true,
  artifactGatekeeperAccepted:true,artifactFirmwareVerified:true,
  developerIDSigned:true,notarized:true}' > "$valid_onboarding"
onboarding_status="$test_dir/onboarding-status.json"
jq --arg evidence "$valid_onboarding" '
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pending" | .evidence = "isolated onboarding fixture") |
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pending" | .evidence = "isolated onboarding fixture") |
  (.gates[] | select(.id == "onboarding-qr")) |= (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$onboarding_status"
set +e
onboarding_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$onboarding_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
onboarding_result=$?
set -e
[[ $onboarding_result -eq 1 && "$onboarding_output" == "NOT READY:"* ]] || {
    echo "FAIL: valid onboarding publication evidence was not accepted." >&2
    exit 1
}
jq '.qrSHA256 = ("d" * 64)' "$valid_onboarding" > "$test_dir/invalid-onboarding.json"
jq --arg evidence "$test_dir/invalid-onboarding.json" '
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pending" | .evidence = "isolated onboarding fixture") |
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pending" | .evidence = "isolated onboarding fixture") |
  (.gates[] | select(.id == "onboarding-qr")) |= (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$onboarding_status"
set +e
onboarding_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$onboarding_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
onboarding_result=$?
set -e
[[ $onboarding_result -eq 1 && "$onboarding_output" == "INVALID:"* ]] || {
    echo "FAIL: onboarding publication evidence with a mismatched QR hash was not rejected." >&2
    exit 1
}

valid_recovery="$test_dir/valid-recovery.json"
jq -n --arg telemetryReport "$factory_telemetry_a" \
  --arg telemetrySHA256 "$factory_telemetry_a_sha" \
  --argjson telemetry "$factory_telemetry_summary" \
  '{schemaVersion:2, gate:"local-signed-recovery", result:"pass",
  startedAt:"2026-08-13T14:00:00Z", completedAt:"2026-08-13T14:00:11Z",
  durationSeconds:11, appVersion:"3.1.1", buildNumber:"4", firmwareVersion:"0.6.16",
  protocolVersion:"1.1", signatureKind:"Developer ID Application", hardenedRuntime:true,
  usbReenumerated:true, telemetryHealthy:true, telemetryReport:$telemetryReport,
  telemetrySHA256:$telemetrySHA256,
  packageManifestSHA256:("d" * 64), executableSHA256:("e" * 64),
  telemetry:$telemetry}' > "$valid_recovery"
recovery_status="$test_dir/recovery-status.json"
jq --arg evidence "$valid_recovery" '
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pending" | .evidence = "isolated recovery fixture") |
  (.gates[] | select(.id == "onboarding-qr")) |=
    (.status = "pending" | .evidence = "isolated recovery fixture") |
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$recovery_status"
set +e
recovery_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$recovery_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
recovery_result=$?
set -e
[[ $recovery_result -eq 1 && "$recovery_output" == "NOT READY:"* ]] || {
    echo "FAIL: valid signed recovery evidence was not accepted." >&2
    exit 1
}

jq '.signatureKind = "Apple Development"' "$valid_recovery" > "$test_dir/invalid-recovery.json"
jq --arg evidence "$test_dir/invalid-recovery.json" '
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pending" | .evidence = "isolated recovery fixture") |
  (.gates[] | select(.id == "onboarding-qr")) |=
    (.status = "pending" | .evidence = "isolated recovery fixture") |
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$recovery_status"
set +e
recovery_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$recovery_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
recovery_result=$?
set -e
[[ $recovery_result -eq 1 && "$recovery_output" == "INVALID:"* ]] || {
    echo "FAIL: development-signed recovery evidence was not rejected." >&2
    exit 1
}

jq '.telemetry.maximumInvalidFrameCount = 1' "$valid_recovery" > "$test_dir/unhealthy-recovery.json"
jq --arg evidence "$test_dir/unhealthy-recovery.json" '
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pending" | .evidence = "isolated recovery fixture") |
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$recovery_status"
set +e
recovery_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$recovery_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
recovery_result=$?
set -e
[[ $recovery_result -eq 1 && "$recovery_output" == "INVALID:"* ]] || {
    echo "FAIL: unhealthy recovery telemetry evidence was not rejected." >&2
    exit 1
}

valid_power="$test_dir/valid-power.json"
power_telemetry="$test_dir/power-telemetry.jsonl"
for elapsed in 1000 6000; do
    jq -nc --argjson elapsed "$elapsed" \
      '{elapsedMilliseconds:$elapsed,telemetry:{firmwareVersion:"0.6.16",
        framesPerSecond:8.4,minimumFreeHeapBytes:162280,invalidFrameCount:0,
        touchReadErrorCount:0,touchControllerPresent:true,resetReason:"power_on"}}' \
      >> "$power_telemetry"
done
power_telemetry_sha=$(shasum -a 256 "$power_telemetry" | awk '{print $1}')
power_telemetry_summary=$(Scripts/notchagent-desk-telemetry-evidence.sh "$power_telemetry" power_on)
jq -n --slurpfile package firmware/notchagent_desk/release/manifest.json \
  --arg telemetryReport "$power_telemetry" --arg telemetrySHA256 "$power_telemetry_sha" \
  --argjson telemetry "$power_telemetry_summary" \
  '{schemaVersion:3, gate:"abrupt-power-recovery", result:"pass",
  startedAt:"2026-08-13T14:00:00Z", disconnectedAt:"2026-08-13T14:00:05Z",
  reconnectedAt:"2026-08-13T14:00:09Z", completedAt:"2026-08-13T14:00:20Z",
  disconnectObservedAfterSeconds:5, reconnectSeconds:4, firmwareVersion:"0.6.16",
  protocolVersion:"1.1",firmwareImageSHA256:$package[0].imageSHA256,
  firmwareSourceSHA256:$package[0].sourceSHA256,
  usbReenumerated:true, telemetryHealthy:true,
  telemetryReport:$telemetryReport,telemetrySHA256:$telemetrySHA256,
  telemetry:$telemetry}' > "$valid_power"
power_status="$test_dir/power-status.json"
jq --arg evidence "$valid_power" '
  (.gates[] | select(.id == "abrupt-power-recovery")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$power_status"
set +e
power_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$power_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
power_result=$?
set -e
[[ $power_result -eq 1 && "$power_output" == "NOT READY:"* ]] || {
    echo "FAIL: valid abrupt-power evidence was not accepted." >&2
    exit 1
}

jq '.reconnectSeconds = 121' "$valid_power" > "$test_dir/invalid-power.json"
jq --arg evidence "$test_dir/invalid-power.json" '
  (.gates[] | select(.id == "abrupt-power-recovery")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$power_status"
set +e
power_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$power_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
power_result=$?
set -e
[[ $power_result -eq 1 && "$power_output" == "INVALID:"* ]] || {
    echo "FAIL: slow abrupt-power recovery evidence was not rejected." >&2
    exit 1
}

valid_notarization="$test_dir/valid-notarization.json"
jq -n '{schemaVersion:2, gate:"developer-id-notarization", result:"pass",
  completedAt:"2026-08-13T14:00:00Z", bundleIdentifier:"br.com.lfrprojects.notchagent",
  appVersion:"3.1.1", buildNumber:"4", signatureKind:"Developer ID Application",
  hardenedRuntime:true, notarizationStatus:"Accepted", stapleValidated:true,
  gatekeeperAccepted:true, executableSHA256:("a" * 64),
  releaseAssetFilename:"NotchAgent-Desk-Beta1-3.1.1.zip",
  releaseAssetSHA256:("c" * 64)}' > "$valid_notarization"
notarization_status="$test_dir/notarization-status.json"
jq --arg evidence "$valid_notarization" '
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pending" | .evidence = "isolated notarization fixture") |
  (.gates[] | select(.id == "onboarding-qr")) |=
    (.status = "pending" | .evidence = "isolated notarization fixture") |
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$notarization_status"
set +e
notarization_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$notarization_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
notarization_result=$?
set -e
[[ $notarization_result -eq 1 && "$notarization_output" == "NOT READY:"* ]] || {
    echo "FAIL: valid notarization evidence was not accepted by the Beta 1 gate." >&2
    exit 1
}

linked_release_status="$test_dir/linked-release-status.json"
linked_onboarding="$test_dir/linked-onboarding.json"
notarization_sha=$(shasum -a 256 "$valid_notarization" | awk '{print $1}')
jq --arg sha "$notarization_sha" '.notarizationEvidenceSHA256 = $sha' \
  "$valid_onboarding" > "$linked_onboarding"
jq --arg notarization "$valid_notarization" --arg onboarding "$linked_onboarding" '
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pending" | .evidence = "isolated release-link fixture") |
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pass" | .evidence = $notarization) |
  (.gates[] | select(.id == "onboarding-qr")) |=
    (.status = "pass" | .evidence = $onboarding)
' $status_fixture > "$linked_release_status"
set +e
linked_release_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$linked_release_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
linked_release_result=$?
set -e
[[ $linked_release_result -eq 1 && "$linked_release_output" == "NOT READY:"* ]] || {
    echo "FAIL: matching notarized and published release asset hashes were not accepted." >&2
    exit 1
}

recovery_notary_status="$test_dir/recovery-notary-status.json"
jq --arg recovery "$valid_recovery" --arg notarization "$valid_notarization" '
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pass" | .evidence = $recovery) |
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pass" | .evidence = $notarization) |
  (.gates[] | select(.id == "onboarding-qr")) |=
    (.status = "pending" | .evidence = "isolated recovery-notarization fixture")
' $status_fixture > "$recovery_notary_status"
set +e
recovery_notary_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$recovery_notary_status" \
  Scripts/notchagent-desk-beta1-gate.sh 2>&1)
recovery_notary_result=$?
set -e
[[ $recovery_notary_result -eq 1 && "$recovery_notary_output" == "INVALID:"* ]] || {
    echo "FAIL: Beta gate accepted recovery with a different executable than notarization." >&2
    exit 1
}

jq '.releaseAssetSHA256 = ("f" * 64)' "$linked_onboarding" > "$test_dir/mismatched-release-onboarding.json"
jq --arg notarization "$valid_notarization" --arg onboarding "$test_dir/mismatched-release-onboarding.json" '
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pending" | .evidence = "isolated release-link fixture") |
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pass" | .evidence = $notarization) |
  (.gates[] | select(.id == "onboarding-qr")) |=
    (.status = "pass" | .evidence = $onboarding)
' $status_fixture > "$linked_release_status"
set +e
linked_release_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$linked_release_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
linked_release_result=$?
set -e
[[ $linked_release_result -eq 1 && "$linked_release_output" == "INVALID:"* ]] || {
    echo "FAIL: onboarding accepted an asset different from the notarized release ZIP." >&2
    exit 1
}

jq '.executableSHA256 = "invalid"' "$valid_notarization" > "$test_dir/invalid-notarization.json"
jq --arg evidence "$test_dir/invalid-notarization.json" '
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pending" | .evidence = "isolated notarization fixture") |
  (.gates[] | select(.id == "onboarding-qr")) |=
    (.status = "pending" | .evidence = "isolated notarization fixture") |
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$notarization_status"
set +e
notarization_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$notarization_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
notarization_result=$?
set -e
[[ $notarization_result -eq 1 && "$notarization_output" == "INVALID:"* ]] || {
    echo "FAIL: invalid notarization evidence was not rejected." >&2
    exit 1
}

jq '.appVersion = "3.0.0" | .executableSHA256 = ("a" * 64)' "$valid_notarization" > "$test_dir/old-version-notarization.json"
jq --arg evidence "$test_dir/old-version-notarization.json" '
  (.gates[] | select(.id == "local-signed-recovery")) |=
    (.status = "pending" | .evidence = "isolated notarization fixture") |
  (.gates[] | select(.id == "onboarding-qr")) |=
    (.status = "pending" | .evidence = "isolated notarization fixture") |
  (.gates[] | select(.id == "developer-id-notarization")) |=
    (.status = "pass" | .evidence = $evidence)
' $status_fixture > "$notarization_status"
set +e
notarization_output=$(NOTCHAGENT_DESK_BETA1_STATUS_FILE="$notarization_status" Scripts/notchagent-desk-beta1-gate.sh 2>&1)
notarization_result=$?
set -e
[[ $notarization_result -eq 1 && "$notarization_output" == "INVALID:"* ]] || {
    echo "FAIL: notarization evidence for already-published app 3.0.0 was not rejected." >&2
    exit 1
}

echo "PASS: Desk pilot, procurement, matrix, factory, recovery, notarization, and Beta 1 contracts reject incomplete evidence, unhealthy metrics, private fields, and status tampering."
