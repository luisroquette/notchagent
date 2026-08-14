#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

pilot_file="${1:-}"
[[ -f "$pilot_file" && ! -L "$pilot_file" ]] || {
    echo "Usage: $0 /path/to/private-pilot.json (regular file required)" >&2
    exit 2
}

jq -e '
  def day_epoch: (. + "T00:00:00Z" | fromdateiso8601);
  .schemaVersion == 6 and
  (keys | sort) == ["participants","pilotAlias","schemaVersion","severity1Defects"] and
  (.pilotAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
  (.severity1Defects | type) == "number" and .severity1Defects == 0 and
  (.participants | length) == 5 and
  ([.participants[].participantAlias] | unique | length) == 5 and
  ([.participants[].unitAlias] | unique | length) == 5 and
  all(.participants[];
    (keys | sort) == ["consentEvidenceFile","consentEvidenceSHA256","days","macClass","macOSMajor","participantAlias","unitAlias","usable"] and
    (.consentEvidenceFile | type == "string" and test("\\S")) and
    (.consentEvidenceSHA256 | test("^[0-9a-f]{64}$")) and
    (.participantAlias | test("^P[0-9]{2}$")) and
    (.unitAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
    (.macClass | test("^[a-z0-9][a-z0-9-]{2,47}$")) and
    (.macOSMajor | type) == "number" and .macOSMajor == (.macOSMajor | floor) and .macOSMajor >= 14 and
    (.days | length) == 7 and
    ([.days[].date] | unique | length) == 7 and
    (([.days[].date | day_epoch] | sort) as $dates |
      all(range(1; ($dates | length)); ($dates[.] - $dates[. - 1]) == 86400)) and
    all(.days[];
      (keys | sort) == ["connectionSeconds","connectionSuccess","date","dockAlias","dockClass","firmwareVersion","healthPass","maximumTouchLatencyMs","minimumFramesPerSecond","minimumFreeHeapBytes","resetAnomalyCount","sourceReport","sourceReportSHA256","touchObserved","updateResult"] and
      (.date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and
      (.connectionSuccess | type) == "boolean" and
      (.connectionSeconds | type) == "number" and .connectionSeconds >= 0 and
      (.dockClass == "direct" or .dockClass == "dock" or .dockClass == "hub") and
      (.dockAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
      .firmwareVersion == "0.6.16" and
      (if .connectionSuccess then
        .healthPass == true and
        .touchObserved == true and
        (.sourceReport | type) == "string" and (.sourceReport | test("\\S")) and
        (.sourceReportSHA256 | test("^[0-9a-f]{64}$")) and
        (.resetAnomalyCount | type) == "number" and .resetAnomalyCount == 0 and
        (.minimumFreeHeapBytes | type) == "number" and .minimumFreeHeapBytes >= 122880 and
        (.minimumFramesPerSecond | type) == "number" and .minimumFramesPerSecond >= 7 and
        (.maximumTouchLatencyMs | type) == "number" and
          .maximumTouchLatencyMs >= 0 and .maximumTouchLatencyMs <= 100
      else
        .healthPass == false and
        .touchObserved == false and
        .sourceReport == null and
        .sourceReportSHA256 == null and
        .resetAnomalyCount == null and
        .minimumFreeHeapBytes == null and
        .minimumFramesPerSecond == null and
        .maximumTouchLatencyMs == null
      end) and
      (.updateResult == "not_attempted" or .updateResult == "pass")
    ) and
    (if .usable.recovery then
      any(.days[]; .updateResult == "pass")
    else true end) and
    (.usable | keys | sort) == ["alerts","recovery","runner","swipe","touch"] and
    (.usable | all(.[]; type == "boolean"))
  ) and
  ([.participants[].days[].date] | unique | length) == 7 and
  ([.participants[].macClass] | unique | length) >= 2 and
  ([.participants[].days[]] as $days |
    ($days | length) == 35 and
    ($days | map(select(.connectionSuccess == true)) | length) >= 34 and
    ($days | map(select(.connectionSuccess == true and .connectionSeconds <= 10)) | length) >= 34 and
    ([$days[] | select(.connectionSuccess == true) | .sourceReportSHA256] | unique | length) ==
      ($days | map(select(.connectionSuccess == true)) | length) and
    ([$days[] | select(.dockClass != "direct") | .dockAlias] | unique | length) >= 2
  ) and
  ([.participants[] | select(.usable.touch == true)] | length) >= 4 and
  ([.participants[] | select(.usable.swipe == true)] | length) >= 4 and
  ([.participants[] | select(.usable.runner == true)] | length) >= 4 and
  ([.participants[] | select(.usable.alerts == true)] | length) >= 4 and
  ([.participants[] | select(.usable.recovery == true)] | length) >= 4 and
  ([.. | objects | keys[] | ascii_downcase] |
    all(.[];
      test("credential|password|secret|token|account|serialpath|serialnumber|hostname|hardwareuuid|macaddress|email|fullname|prompt|financial|billing") | not
    )
  )
' "$pilot_file" >/dev/null || {
    echo "NOT READY: pilot data does not satisfy the 5-user × 7-day acceptance contract." >&2
    exit 1
}

all_consent_documents=()
all_consent_document_shas=()
while IFS= read -r participant; do
    participant_alias=$(jq -r '.participantAlias' <<<"$participant")
    consent_evidence=$(jq -r '.consentEvidenceFile' <<<"$participant")
    consent_evidence_sha=$(jq -r '.consentEvidenceSHA256' <<<"$participant")
    [[ -f "$consent_evidence" && ! -L "$consent_evidence" &&
       "$(shasum -a 256 "$consent_evidence" | awk '{print $1}')" == "$consent_evidence_sha" ]] || {
        echo "NOT READY: $participant_alias consent record is missing, linked, or changed." >&2
        exit 1
    }
    Scripts/notchagent-desk-consent-gate.sh "$consent_evidence" "$participant_alias" >/dev/null || exit 1
    consent_document=$(jq -r '.documentFile' "$consent_evidence")
    consent_document_sha=$(jq -r '.documentSHA256' "$consent_evidence")
    all_consent_documents+=("$consent_document")
    all_consent_document_shas+=("$consent_document_sha")
done < <(jq -c '.participants[]' "$pilot_file")

unique_consent_documents=$(printf '%s\n' "${all_consent_documents[@]}" | sort -u | wc -l | tr -d '[:space:]')
unique_consent_shas=$(printf '%s\n' "${all_consent_document_shas[@]}" | sort -u | wc -l | tr -d '[:space:]')
(( unique_consent_documents == 5 && unique_consent_shas == 5 )) || {
    echo "NOT READY: every participant requires a unique consent document." >&2
    exit 1
}

while IFS= read -r day; do
    source_report=$(jq -r '.sourceReport' <<<"$day")
    [[ -f "$source_report" && ! -L "$source_report" ]] || {
        echo "NOT READY: pilot day source is missing or is a symlink: $source_report" >&2
        exit 1
    }
    recomputed=$(Scripts/notchagent-desk-pilot-day.sh "$source_report" \
      "$(jq -r '.date' <<<"$day")" "$(jq -r '.dockClass' <<<"$day")" \
      "$(jq -r '.dockAlias' <<<"$day")" "$(jq -r '.updateResult' <<<"$day")") || {
        echo "NOT READY: pilot day source is unhealthy: $source_report" >&2
        exit 1
    }
    jq -e --argjson recomputed "$recomputed" '. == $recomputed' <<<"$day" >/dev/null || {
        echo "NOT READY: pilot day summary does not match its source: $source_report" >&2
        exit 1
    }
done < <(jq -c '.participants[].days[] | select(.connectionSuccess == true)' "$pilot_file")

echo "PASS: pilot cohort satisfies onboarding, reliability, usability, privacy, and coverage gates."
