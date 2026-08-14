#!/usr/bin/env bash
set -euo pipefail

export ARDUINO_DIRECTORIES_USER="${ARDUINO_DIRECTORIES_USER:-${NOTCHAGENT_ARDUINO_USER_DIR:-${HOME:?}/Library/Application Support/NotchAgent/Arduino}}"

sketch_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$sketch_dir/verify-toolchain.sh" >/dev/null
release_dir="$sketch_dir/release"
firmware_version="$(sed -n 's/^#define DESK_FW_VERSION "\([0-9][0-9.]*\)"$/\1/p' "$sketch_dir/config.h")"
[[ "$firmware_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid DESK_FW_VERSION" >&2
  exit 2
}

esptool_path="${NOTCHAGENT_ESPTOOL_PATH:-$HOME/Library/Arduino15/packages/esp32/tools/esptool_py/5.2.0/esptool}"
esptool_license="$(dirname "$esptool_path")/LICENSE"
[[ -x "$esptool_path" && -f "$esptool_license" ]] || {
  echo "Pinned esptool 5.2.0 and its license are required." >&2
  exit 2
}

source_sha=$(
  cd "$sketch_dir"
  shasum -a 256 \
    config.h desk_protocol.h lv_conf.h notchagent_desk.ino \
    consume-stdin.sh package-release.sh package_manifest.swift partitions.csv touch.h \
    trim_factory.swift verify-toolchain.sh \
    | shasum -a 256 | awk '{print $1}'
)
if [[ -f "$release_dir/manifest.json" && -f "$release_dir/NotchAgentDesk-factory.bin" &&
      -x "$release_dir/esptool" && -f "$release_dir/esptool-LICENSE.txt" ]] &&
   jq -e --arg version "$firmware_version" --arg sourceSHA256 "$source_sha" '
     .schemaVersion == 2 and .firmwareVersion == $version and .sourceSHA256 == $sourceSHA256
   ' "$release_dir/manifest.json" >/dev/null 2>&1 &&
   "$sketch_dir/verify-release.sh" "$release_dir" >/dev/null 2>&1; then
  echo "Reusing verified NotchAgent Desk firmware $firmware_version for source $source_sha"
  exit 0
fi

build_dir="$(mktemp -d)"
cleanup() {
  [[ -n "$build_dir" && -d "$build_dir" && "$build_dir" == "${TMPDIR:-/tmp}"* ]] || return 1
  rm -r -- "$build_dir"
}
trap cleanup EXIT

flags="-DLV_CONF_INCLUDE_SIMPLE -I${sketch_dir}"
fqbn="esp32:esp32:esp32s3:PSRAM=opi,FlashSize=16M,PartitionScheme=custom,CDCOnBoot=cdc,USBMode=hwcdc,FlashMode=qio"
# The sketch is valid ordered C++; generated Arduino prototypes are unnecessary.
# Skipping legacy ctags avoids nondeterministic hangs in local and factory builds.
arduino-cli compile --jobs 4 --warnings all --fqbn "$fqbn" \
  --build-property "tools.ctags.pattern=$sketch_dir/consume-stdin.sh" \
  --build-property "compiler.cpp.extra_flags=$flags" \
  --build-property "compiler.c.extra_flags=$flags" \
  --output-dir "$build_dir" "$sketch_dir"

mkdir -p "$release_dir"
install -m 0644 "$build_dir/notchagent_desk.ino.merged.bin" "$release_dir/NotchAgentDesk-factory.bin"
swift "$sketch_dir/trim_factory.swift" "$release_dir/NotchAgentDesk-factory.bin"
install -m 0755 "$esptool_path" "$release_dir/esptool"
install -m 0644 "$esptool_license" "$release_dir/esptool-LICENSE.txt"
swift "$sketch_dir/package_manifest.swift" "$firmware_version" \
  "$release_dir/NotchAgentDesk-factory.bin" "$release_dir/esptool" "$source_sha" \
  "$release_dir/manifest.json"
"$sketch_dir/verify-release.sh" "$release_dir"

echo "Packaged NotchAgent Desk firmware $firmware_version in $release_dir"
