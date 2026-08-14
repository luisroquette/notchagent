#!/usr/bin/env bash
set -euo pipefail

export ARDUINO_DIRECTORIES_USER="${ARDUINO_DIRECTORIES_USER:-${NOTCHAGENT_ARDUINO_USER_DIR:-${HOME:?}/Library/Application Support/NotchAgent/Arduino}}"

sketch_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$sketch_dir/verify-toolchain.sh" >/dev/null
fqbn="esp32:esp32:esp32s3:PSRAM=opi,FlashSize=16M,PartitionScheme=custom,CDCOnBoot=cdc,USBMode=hwcdc,FlashMode=qio"
command_name="${1:-build}"
port="${2:-}"
flags="-DLV_CONF_INCLUDE_SIMPLE -I${sketch_dir}"
ctags_override="tools.ctags.pattern=$sketch_dir/consume-stdin.sh"

case "$command_name" in
  build)
    arduino-cli compile --jobs 4 --warnings all --fqbn "$fqbn" \
      --build-property "$ctags_override" \
      --build-property "compiler.cpp.extra_flags=$flags" \
      --build-property "compiler.c.extra_flags=$flags" "$sketch_dir"
    ;;
  upload)
    if [[ -z "$port" || "$port" != /dev/cu.usbmodem* ]]; then
      echo "Usage: ./build.sh upload /dev/cu.usbmodemXXXX" >&2
      exit 2
    fi
    [[ -c "$port" ]] || { echo "Serial port not found: $port" >&2; exit 2; }
    arduino-cli compile --jobs 4 --warnings all --fqbn "$fqbn" \
      --build-property "$ctags_override" \
      --build-property "compiler.cpp.extra_flags=$flags" \
      --build-property "compiler.c.extra_flags=$flags" \
      --upload -p "$port" "$sketch_dir"
    ;;
  monitor)
    if [[ -z "$port" || ! -c "$port" ]]; then
      echo "Usage: ./build.sh monitor /dev/cu.usbmodemXXXX" >&2
      exit 2
    fi
    exec arduino-cli monitor -p "$port" -c baudrate=115200
    ;;
  *)
    echo "Usage: ./build.sh [build|upload PORT|monitor PORT]" >&2
    exit 2
    ;;
esac
