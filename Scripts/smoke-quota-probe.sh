#!/bin/bash
# Smoke test: valida o fluxo COMPLETO do percentual de cota do Claude em
# produção — token → probe → headers → parse → snapshot → card. Foi criado
# depois do incidente do domínio de prefs (swift run lia defaults vazios):
# se qualquer elo quebrar de novo, este script aponta QUAL em segundos.
#
# Uso: Scripts/smoke-quota-probe.sh   (roda o app e espera o snapshot)

set -u
APP_SUPPORT="$HOME/Library/Application Support/NotchAgent"
SNAPSHOT="$APP_SUPPORT/snapshots.json"
LOG="$APP_SUPPORT/app.log"
TIMEOUT_SECS=180

echo "[smoke] procurando instância em execução…"
if pgrep -f "NotchAgent" >/dev/null 2>&1; then
    echo "[smoke] instância já roda — usando-a (o refresh acontece a cada 60s)"
else
    echo "[smoke] abrindo o app…"
    (cd "$(dirname "$0")/.." && swift run NotchAgent >/tmp/na-smoke.log 2>&1 &)
fi

echo "[smoke] esperando o snapshot ganhar percentual (até ${TIMEOUT_SECS}s)…"
START=$(date +%s)
while true; do
    if [ -f "$SNAPSHOT" ]; then
        RESULT=$(python3 - "$SNAPSHOT" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
for d in data:
    if isinstance(d, dict) and d.get('provider') == 'claude-code':
        w = d.get('weekly') or {}
        s = d.get('session') or {}
        print(f"quotaStatus={d.get('quotaStatus')} weekly%={w.get('usedPercent')} session%={s.get('usedPercent')} resets={w.get('resetsAt')}")
        if w.get('usedPercent') is not None or d.get('quotaStatus') is not None:
            sys.exit(0)
sys.exit(1)
EOF
)
        CODE=$?
        if [ $CODE -eq 0 ]; then
            echo "[smoke] OK: $RESULT"
            exit 0
        fi
        echo "[smoke] ainda sem percentual: $RESULT"
    fi
    NOW=$(date +%s)
    if [ $((NOW - START)) -gt "$TIMEOUT_SECS" ]; then
        echo "[smoke] FALHOU após ${TIMEOUT_SECS}s. Diagnóstico:"
        echo "  - prefs (probe): $(defaults read br.com.lfrprojects.notchagent app.settings.v1 2>/dev/null | head -c 200)"
        echo "  - últimas linhas do app.log:"
        tail -10 "$LOG" 2>/dev/null || echo "    (app.log não existe — o probe nunca logou)"
        exit 1
    fi
    sleep 10
done
