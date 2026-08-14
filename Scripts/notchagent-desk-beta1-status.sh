#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

status_file="${NOTCHAGENT_DESK_BETA1_STATUS_FILE:-docs/evidence/notchagent-desk-beta1-status.json}"
[[ -f "$status_file" && ! -L "$status_file" ]] || {
    echo "INVALID: Beta 1 status file is missing or linked." >&2
    exit 1
}

soak='null'
if soak_json=$(Scripts/notchagent-desk-soak-status.sh 2>/dev/null); then
    soak=$(jq -c '{running,healthy,elapsedSeconds,samples,firmwareVersion,
      maximumSampleGapMilliseconds,maximumWallClockGapSeconds,
      minimumFramesPerSecond,minimumFreeHeapBytes,maximumInvalidFrameCount,
      maximumTouchReadErrorCount,reliabilityFailures}' <<<"$soak_json")
fi

jq -n --slurpfile status "$status_file" --argjson soak "$soak" '
  def category($id):
    if $id == "soak-24-hours" and ($soak.running // false) then "in_progress"
    elif (["physical-touch-latency","physical-reconnect-100","abrupt-power-recovery"] | index($id)) then "physical_action"
    elif (["developer-id-notarization","onboarding-qr","dock-hub-mac-matrix",
           "bom-enclosure-cable-freeze","five-user-seven-day-pilot","local-signed-recovery"] | index($id)) then "external_gate"
    else "implementation" end;
  {schemaVersion:1,product:$status[0].product,statusUpdatedAt:$status[0].updatedAt,
   counts:{pass:([$status[0].gates[]|select(.status=="pass")]|length),
           waived:([$status[0].gates[]|select(.status=="waived")]|length),
           pending:([$status[0].gates[]|select(.status=="pending")]|length),
           fail:([$status[0].gates[]|select(.status=="fail")]|length)},
   soak:$soak,
   openGates:[$status[0].gates[]|select(.status!="pass" and .status!="waived")|
     {id,status,category:category(.id),evidence}]}
'
