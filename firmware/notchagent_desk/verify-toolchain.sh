#!/usr/bin/env bash
set -euo pipefail

export ARDUINO_DIRECTORIES_USER="${ARDUINO_DIRECTORIES_USER:-${NOTCHAGENT_ARDUINO_USER_DIR:-${HOME:?}/Library/Application Support/NotchAgent/Arduino}}"

require_version() {
  local component="$1"
  local actual="$2"
  local expected="$3"
  [[ "$actual" == "$expected" ]] || {
    echo "Invalid firmware toolchain: $component $actual; expected $expected." >&2
    exit 1
  }
}

command -v arduino-cli >/dev/null 2>&1 || {
  echo "Invalid firmware toolchain: arduino-cli is not installed." >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "Invalid firmware toolchain: jq is not installed." >&2
  exit 1
}

cli_version=$(arduino-cli version --format json | jq -er '.VersionString')
core_version=$(arduino-cli core list --format json |
  jq -er '.platforms[] | select(.id == "esp32:esp32") | .installed_version')
libraries_json=$(arduino-cli lib list --format json)
library_version() {
  jq -er --arg name "$1" \
    '.installed_libraries[] | select(.library.name == $name) | .library.version' \
    <<<"$libraries_json"
}

require_version "arduino-cli" "$cli_version" "1.5.1"
require_version "esp32:esp32" "$core_version" "3.3.8"
require_version "lvgl" "$(library_version lvgl)" "9.2.2"
require_version "GFX Library for Arduino" "$(library_version 'GFX Library for Arduino')" "1.6.5"
require_version "ArduinoJson" "$(library_version ArduinoJson)" "7.2.0"

echo "PASS: pinned NotchAgent Desk firmware toolchain verified."
