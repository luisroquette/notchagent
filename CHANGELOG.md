# Changelog

## 1.0.0 — 2026-07-14

Primeira versão completa.

### Core
- Providers plugin-like: Claude Code (transcripts + probe de quota oficial na API), Codex (rate limits exatos dos rollouts, janelas classificadas por duração), Gemini CLI (atividade; tokens declarados indisponíveis).
- Scheduler central com refresh concorrente, cache de parse por arquivo, persistência JSON (snapshots + histórico 30d), refresh no wake.
- Semântica única de produto: **% restante do limite** (tanque de combustível) em toda a UI.

### Notch
- Overlay com hit-test seletivo (click-through fora da forma), geometria redetectada em mudança de tela/espaço/wake, fallback pill sem notch.
- Compacto: Claude à esquerda, Codex à direita, com nome + janela (5H/WK) + % restante + micro-medidor.
- Expandido: 4 páginas (NOW / BURN / RHYTHM / MODELS), scroll lateral de trackpad, transições deslizantes, haptics, Esc fecha, countdowns vivos.
- Alertas escalonados em 25/15/10/5% livres com takeover animado progressivamente mais grave; 5% requer clique; notificação do sistema junto.
- Design system "retro hardware gauge": preto + coral, numerais SF Rounded heavy, medidores segmentados, mascote pixel-art procedural que reage à quota.

### Distribuição
- `Scripts/make-app.sh`: .app completo a partir do SwiftPM (Info.plist, ícone .icns gerado por código, assinatura ad-hoc).
- Launch at login (SMAppService) e notificações — ativos no bundle.

### Qualidade
- 52 testes (parsers com fixtures reais, agregador, thresholds, burn rate, pricing, geometria, integração end-to-end por provider).
