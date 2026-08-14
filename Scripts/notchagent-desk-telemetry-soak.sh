#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

duration_seconds="${1:-86400}"
[[ "$duration_seconds" =~ '^[1-9][0-9]*$' ]] || {
    echo "Usage: $0 [duration-seconds]" >&2
    exit 2
}

port=$(Scripts/notchagent-desk-resolve-port.sh)
owner=$(lsof -t "$port" 2>/dev/null | head -1 || true)
[[ -z "$owner" ]] || {
    echo "FAIL: $port is in use. Quit NotchAgent before the firmware-only soak." >&2
    exit 1
}

report_dir="${TMPDIR:-/tmp}/notchagent-desk-telemetry-soak"
mkdir -p "$report_dir"
report="$report_dir/telemetry-soak-$(date -u +%Y%m%dT%H%M%SZ).jsonl"

NOTCHAGENT_DESK_PHYSICAL_TELEMETRY=1 \
NOTCHAGENT_DESK_PORT="$port" \
NOTCHAGENT_DESK_TELEMETRY_DURATION_SECONDS="$duration_seconds" \
NOTCHAGENT_DESK_TELEMETRY_REPORT="$report" \
NOTCHAGENT_DISABLE_PAID_PROBES=1 \
swift test --filter NotchAgentDeskTests/testPhysicalTelemetryWhenExplicitlyEnabled

echo "PASS: firmware telemetry remained healthy for ${duration_seconds}s"
echo "Report: $report"
