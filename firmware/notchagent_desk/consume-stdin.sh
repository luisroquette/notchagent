#!/usr/bin/env bash
set -euo pipefail

# Arduino invokes ctags with the preprocessed sketch on stdin. The Desk sketch
# is already valid ordered C++, so consume that stream without producing tags.
while IFS= read -r _; do :; done
