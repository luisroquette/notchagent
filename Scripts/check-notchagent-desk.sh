#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

export ARDUINO_DIRECTORIES_USER="${ARDUINO_DIRECTORIES_USER:-${NOTCHAGENT_ARDUINO_USER_DIR:-${HOME:?}/Library/Application Support/NotchAgent/Arduino}}"

# NotchAgent (VERSION/BUILD_NUMBER, raiz do repo) e NotchAgent Desk
# (docs/NOTCHAGENT_DESK_RELEASE.json) são produtos SEPARADOS, com ciclos de release
# independentes — confirmado pelo dono em 17/08/2026. Este gate comparava os dois e travava
# toda release do produto principal que não coincidisse por acaso com a versão do Desk (ex.:
# VERSION 3.3.0 vs appVersion 3.1.2, depois de 3 releases do principal sem tocar no Desk).
# A checagem fazia sentido só na v3.1.1 (ec14e39, quando o script nasceu e os dois produtos
# ainda eram a mesma versão) — deixou de valer assim que divergiram de propósito.

Scripts/check-github-actions-pins.sh

command -v arduino-cli >/dev/null || {
    echo "ERROR: arduino-cli is not installed." >&2
    exit 1
}

core_version=$(arduino-cli core list | awk '$1 == "esp32:esp32" { print $2; exit }')
[[ "$core_version" == "3.3.8" ]] || {
    echo "ERROR: esp32 core 3.3.8 is required; found ${core_version:-none}." >&2
    exit 1
}

libraries=$(arduino-cli lib list)
grep -Eq '^lvgl[[:space:]]+9\.2\.2([[:space:]]|$)' <<<"$libraries" || {
    echo "ERROR: lvgl 9.2.2 is required." >&2
    exit 1
}
grep -Eq '^ArduinoJson[[:space:]]+7\.2\.0([[:space:]]|$)' <<<"$libraries" || {
    echo "ERROR: ArduinoJson 7.2.0 is required." >&2
    exit 1
}
grep -Eq '^GFX Library for Arduino[[:space:]]+1\.6\.5([[:space:]]|$)' <<<"$libraries" || {
    echo "ERROR: Arduino_GFX 1.6.5 is required." >&2
    exit 1
}

firmware/notchagent_desk/package-release.sh
Scripts/notchagent-desk-contract-tests.sh
NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test
Scripts/notchagent-desk-distribution-contract-tests.sh
Scripts/audit-public-release.sh
git diff --check
echo "OK: NotchAgent Desk contract, privacy tests, firmware, and public audit passed."
