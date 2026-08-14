#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

output="${1:-}"
start_date="${2:-}"
[[ "$output" == /* && ! -e "$output" && -d "${output:h}" ]] || {
    echo "Usage: $0 /absolute/new-private-pilot.json YYYY-MM-DD" >&2
    exit 2
}
[[ "$start_date" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ]] &&
  date -j -f %Y-%m-%d "$start_date" +%Y-%m-%d >/dev/null 2>&1 || {
    echo "INVALID: start date must be a real YYYY-MM-DD date." >&2
    exit 2
}

jq -n --arg startDate "$start_date" '
  def pilot_date($day):
    (($startDate + "T00:00:00Z" | fromdateiso8601) + ($day * 86400) | strftime("%Y-%m-%d"));
  def dock_class($participant):
    if $participant == 0 then "dock" elif $participant == 1 then "hub" else "direct" end;
  def dock_alias($participant):
    if $participant == 0 then "DOCK-A" elif $participant == 1 then "HUB-A" else "DIRECT" end;
  {schemaVersion:6, pilotAlias:"BETA1-A", severity1Defects:0,
   participants:[range(0; 5) as $participant |
    {participantAlias:("P0" + (($participant + 1) | tostring)),
     unitAlias:("DESK-B1-00" + (($participant + 1) | tostring)),
     macClass:(if $participant < 3 then "mac-class-pending-a" else "mac-class-pending-b" end),
     macOSMajor:14,consentEvidenceFile:null,consentEvidenceSHA256:null,
     days:[range(0; 7) as $day |
       {date:pilot_date($day), connectionSuccess:false, connectionSeconds:0,
        dockClass:dock_class($participant), dockAlias:dock_alias($participant),
        firmwareVersion:"0.6.16", healthPass:false, resetAnomalyCount:null,
        minimumFreeHeapBytes:null, minimumFramesPerSecond:null,
        maximumTouchLatencyMs:null, touchObserved:false, sourceReport:null,sourceReportSHA256:null,
        updateResult:"not_attempted"}],
     usable:{touch:false,swipe:false,runner:false,alerts:false,recovery:false}}]}
' > "$output"

echo "READY: private pilot scaffold created at $output"
echo "NOT READY: record consent, real Mac classes, daily evidence, and final usability before validation."
