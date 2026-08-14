#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

workflows=(.github/workflows/*.yml(N) .github/workflows/*.yaml(N))
(( ${#workflows[@]} > 0 )) || { echo "PASS: no GitHub Actions workflows found."; exit 0; }

for workflow in "${workflows[@]}"; do
    while IFS= read -r action; do
        reference="${action##*@}"
        [[ "$action" == *@* && "$reference" =~ '^[0-9a-f]{40}$' ]] || {
            echo "FAIL: GitHub Action is not pinned to a full commit SHA in $workflow: $action" >&2
            exit 1
        }
    done < <(sed -nE 's/^[[:space:]-]*uses:[[:space:]]*([^[:space:]#]+).*/\1/p' "$workflow")
done

echo "PASS: every GitHub Action is pinned to a full commit SHA."
