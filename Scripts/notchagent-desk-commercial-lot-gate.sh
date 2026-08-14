#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

procurement="${1:-}"
shift $(( $# > 0 ? 1 : 0 ))
[[ -f "$procurement" && ! -L "$procurement" && $# -gt 0 ]] || {
    echo "Usage: $0 private-procurement.json qc-report.json [...]" >&2
    exit 2
}

Scripts/notchagent-desk-procurement-gate.sh "$procurement" >/dev/null
lot_alias=$(jq -er '.lotAlias' "$procurement")
planned_units=$(jq -er '.plannedUnits' "$procurement")
(( $# >= planned_units )) || {
    echo "NOT READY: $lot_alias has $# accepted QC reports for $planned_units planned units." >&2
    exit 1
}

NOTCHAGENT_DESK_LOT_ALIAS="$lot_alias" \
NOTCHAGENT_DESK_FACTORY_MIN_UNITS="$planned_units" \
    Scripts/notchagent-desk-factory-report-gate.sh "$@" >/dev/null

procurement_sha=$(shasum -a 256 "$procurement" | awk '{print $1}')
report_shas=()
report_files=()
for report in "$@"; do
    [[ -f "$report" && ! -L "$report" ]] || {
        echo "NOT READY: factory report is missing or is a symbolic link: $report" >&2
        exit 1
    }
    report_files+=("$report")
    report_shas+=("$(shasum -a 256 "$report" | awk '{print $1}')")
done
report_shas_json=$(printf '%s\n' "${report_shas[@]}" | jq -R . | jq -s .)
report_files_json=$(printf '%s\n' "${report_files[@]}" | jq -R . | jq -s .)

jq -n \
  --arg lotAlias "$lot_alias" \
  --argjson plannedUnits "$planned_units" \
  --argjson acceptedUnits "$#" \
  --arg procurementFile "$procurement" \
  --arg procurementSHA256 "$procurement_sha" \
  --argjson factoryReportFiles "$report_files_json" \
  --argjson factoryReportSHA256s "$report_shas_json" \
  '{schemaVersion:2,gate:"commercial-lot-freeze",result:"pass",lotAlias:$lotAlias,
    plannedUnits:$plannedUnits,acceptedUnits:$acceptedUnits,
    procurementFile:$procurementFile,
    procurementSHA256:$procurementSHA256,
    factoryReportFiles:$factoryReportFiles,
    factoryReportSHA256s:$factoryReportSHA256s}'
