#!/bin/zsh
set -euo pipefail

explicit_port="${NOTCHAGENT_DESK_PORT:-}"
if [[ -n "$explicit_port" ]]; then
    swift Scripts/notchagent-desk-discover.swift "$explicit_port"
    exit 0
fi

ports=("${(@f)$(swift Scripts/notchagent-desk-discover.swift)}")
[[ ${#ports[@]} -ne 1 || -n "$ports[1]" ]] || ports=()
case ${#ports[@]} in
    0)
        echo "FAIL: no NotchAgent Desk Beta 1 found. Reconnect the device." >&2
        exit 1
        ;;
    1)
        print -r -- "$ports[1]"
        ;;
    *)
        echo "FAIL: multiple NotchAgent Desk devices found; set NOTCHAGENT_DESK_PORT explicitly:" >&2
        print -rl -- "${ports[@]}" >&2
        exit 1
        ;;
esac
