#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

target="${1:-100}"
[[ "$target" =~ '^[1-9][0-9]*$' ]] || {
    echo "Usage: $0 [physical-reconnect-count]" >&2
    exit 2
}

port=$(Scripts/notchagent-desk-resolve-port.sh)
owner=$(lsof -t "$port" 2>/dev/null | head -1 || true)
[[ -z "$owner" ]] || {
    echo "FAIL: $port is in use. Quit NotchAgent before the reconnect test." >&2
    exit 1
}

flasher="firmware/notchagent_desk/release/esptool"
[[ -x "$flasher" ]] || firmware/notchagent_desk/package-release.sh
report_dir="${TMPDIR:-/tmp}/notchagent-desk-reconnect"
mkdir -p "$report_dir"
report="$report_dir/reconnect-$(date -u +%Y%m%dT%H%M%SZ).json"

NOTCHAGENT_DESK_PHYSICAL_RECONNECT_TARGET="$target" \
NOTCHAGENT_DESK_PORT="$port" \
NOTCHAGENT_DESK_FLASHER="$PWD/$flasher" \
NOTCHAGENT_DESK_RECONNECT_REPORT="$report" \
NOTCHAGENT_DISABLE_PAID_PROBES=1 \
swift test --filter NotchAgentDeskTests/testPhysicalResetReconnectCyclesWhenExplicitlyEnabled

echo "PASS: $target physical reset/reconnect cycles"
echo "Report: $report"
