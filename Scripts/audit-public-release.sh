#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

secret_pattern='(sk-admin-[A-Za-z0-9_-]{20,}|sk-or-v1-[A-Fa-f0-9]{32,}|xai-(token-)?[A-Za-z0-9_-]{20,}|ya29\.[A-Za-z0-9_-]{20,}|fc-[A-Fa-f0-9]{24,}|new1_[A-Fa-f0-9]{24,}|gh[opsu]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|A{12,}[A-Za-z0-9%]{40,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)'
personal_pattern='(luisroquette''@gmail\.com|@the_''doom_guy|gen-lang-client-[0-9]{8,}|socialmachine-[0-9]{6,}|K74F''G72F9W|49\.497\.''098/0001-23|Rua Ip[eê]'' Branco|/Users/luis''roquette)'

tmp_files=$(mktemp)
trap 'rm -f "$tmp_files"' EXIT
git ls-files -co --exclude-standard -z > "$tmp_files"

scan_current() {
    local label="$1"
    local pattern="$2"
    local matches
    matches=$(
        xargs -0 rg -l -I --glob '!**/audit-public-release.sh' \
            -e "$pattern" < "$tmp_files" 2>/dev/null || true
    )
    if [[ -n "$matches" ]]; then
        echo "ERRO: $label encontrado em:"
        echo "$matches"
        return 1
    fi
}

scan_history() {
    local matches
    matches=$(
        git grep -l -I -E "$secret_pattern" $(git rev-list --all) \
            -- ':!Scripts/audit-public-release.sh' 2>/dev/null || true
    )
    if [[ -n "$matches" ]]; then
        echo "ERRO: possível segredo encontrado no histórico:"
        echo "$matches" | sed 's/:.*//g' | sort -u
        return 1
    fi
}

scan_new_personal_history() {
    local base="${NOTCHAGENT_PUBLIC_HISTORY_BASE:-}"
    [[ -n "$base" ]] || return 0
    git rev-parse --verify --quiet "${base}^{commit}" >/dev/null || {
        echo "ERRO: baseline público de histórico não existe: $base"
        return 1
    }
    git merge-base --is-ancestor "$base" HEAD || {
        echo "ERRO: histórico atual não avança linearmente o baseline público: $base"
        return 1
    }
    local revisions
    revisions=$(git rev-list "${base}..HEAD")
    [[ -n "$revisions" ]] || return 0
    local matches
    matches=$(git grep -l -I -E "$personal_pattern" $=revisions \
        -- ':!Scripts/audit-public-release.sh' 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        echo "ERRO: identificador pessoal introduzido no novo histórico público:"
        print -r -- "$matches" | sed 's/:.*//g' | sort -u
        return 1
    fi
}

scan_current "possível segredo" "$secret_pattern"
scan_current "identificador pessoal proibido" "$personal_pattern"
scan_history
scan_new_personal_history
echo "OK: arquivos atuais sem segredos/identificadores, histórico sem segredos e novos commits sem identificadores."
