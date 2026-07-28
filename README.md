# NotchAgent

**The fuel gauge for your AI agents, living in your MacBook's notch.**

**Versão atual: 2.0.0** · lançada em 28/07/2026 · [histórico de versões](CHANGELOG.md)

A native macOS menu-bar + notch overlay for Claude Code/Codex quotas and
financial monitoring of external API accounts. It shows provider-reported
spend, balance, plans and quotas with explicit sources and time windows —
local-first, no backend, no telemetry. Swift 6 + SwiftUI/AppKit, zero Electron.

**Also available for Windows** — a system-tray companion (.NET 8 + Avalonia, same parsers, same quota probe) since Windows has no notch. See [`windows/README.md`](windows/README.md) for the current (v1) feature set and build instructions.

![The compact notch bar: Claude on the left wing, Codex on the right](docs/img/notch-compact.png)

![Hover the notch to expand the gauge panel](docs/img/desktop-now.png)

| NOW — % left per provider | BURN — will the session last? |
|---|---|
| ![NOW page](docs/img/panel-now.png) | ![BURN page with projection and scrubbing](docs/img/panel-burn.png) |

| RHYTHM — when do you burn? | MODELS — live probe + cost per model |
|---|---|
| ![RHYTHM page](docs/img/panel-rhythm.png) | ![MODELS page](docs/img/panel-models.png) |

![Low-fuel alert: an escalating takeover fires at 25/15/10/5% left, in light theme here](docs/img/alert-almost-empty.png)

<details>
<summary><b>More screenshots</b> — dashboard, burn scrubbing, settings</summary>

![Burn chart hover scrubbing over the desktop](docs/img/desktop-burn.png)
![Dashboard: session tokens over time + hourly rhythm](docs/img/dashboard-1.png)
![Dashboard: per-provider breakdown](docs/img/dashboard-2.png)
![Settings: appearance, login item, alerts, quota probe](docs/img/settings.png)

</details>

## Install

**Homebrew** (recommended):

```bash
brew install --cask luisroquette/tap/notchagent
xattr -dr com.apple.quarantine /Applications/NotchAgent.app   # free & unsigned — clears Gatekeeper once
open /Applications/NotchAgent.app
```

**Or download** the latest `NotchAgent.app` from [Releases](../../releases), unzip, move to `/Applications`, then clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/NotchAgent.app
open /Applications/NotchAgent.app
```

**Or build from source** (Xcode 15+ / Swift 6 toolchain):

```bash
git clone https://github.com/luisroquette/notchagent.git && cd notchagent
./Scripts/audit-public-release.sh
git config core.hooksPath .githooks
./Scripts/make-app.sh && open dist/NotchAgent.app
```

`make-app.sh` uses the first local Apple Development identity. Override it with
`NOTCHAGENT_SIGN_IDENTITY`; without an identity it falls back to ad-hoc signing.

> **Why trust it?** API credentials stay in the macOS Keychain, portal sessions
> use isolated WebKit profiles, and diagnostics remove credentials, identity and
> financial amounts. Monitoring is opt-in per account. The optional Claude quota
> probe is the only feature that sends a paid one-token model request and can be
> disabled in Settings.

---

**O medidor de combustível dos seus agentes de IA, morando no notch do MacBook.**

Monitor nativo (Swift 6 + SwiftUI/AppKit, zero Electron) de uso, quotas e custos
de Claude Code, Codex, Gemini CLI e contas externas de API. Todas as conexões
são opcionais e vão diretamente do Mac ao provedor configurado.

## O produto

**A pergunta que o NotchAgent responde o tempo todo: "quantos % do meu limite ainda tenho?"**

- **Notch compacto** — Claude na asa esquerda, Codex na direita: nome, `% LEFT` da janela (5H ou WK) colorido por estado, micro-medidor que esvazia como tanque de combustível.
- **Painel expandido** (hover expande, clique fixa, **scroll lateral de trackpad troca de página**, Esc fecha) com 4 páginas:
  - **NOW** — cards por provider: `% restante` gigante, medidor segmentado, "RESETS • 16:30" + countdown vivo, tokens/custo estimado, burn verdict, pills de saúde.
  - **BURN** — gráfico da janela 5h: uso real (linha coral) + projeção pontilhada no ritmo atual + veredito "runs out 16:40 (in 1h 32m)".
  - **RHYTHM** — 24 barras por hora local (hoje/7 dias), hora atual em destaque.
  - **MODELS** — Fable, Opus, Sonnet e Haiku com sonda viva (`OK 0.9s` / `Limited` / `Error`, 1 modelo por ciclo) + uso e custo por modelo dos transcripts.
- **Alertas escalonados em 25/15/10/5% livres** — takeover animado do notch que fica mais grave conforme o fim se aproxima (pulso âmbar → alarme vermelho com mascote tremendo aos 5%, que só sai com clique). Notificação do sistema junto. Um disparo por marco por janela, com rearme no reset.
- **Menu bar** — `% restante` no topo + popover com resumo por provider e controles.
- **Dashboard** — histórico (Swift Charts), ritmo por hora, breakdown diário, log de eventos.
- Fallback elegante em displays sem notch (pill flutuante) e mascote pixel-art procedural como assinatura visual.

## Rodar / Empacotar

```bash
swift run                 # desenvolvimento (menu bar + overlay na hora)
swift test                         # suíte unitária e de integração
./Scripts/audit-public-release.sh # bloqueia segredos e IDs pessoais
./Scripts/make-app.sh              # gera dist/NotchAgent.app
open dist/NotchAgent.app
```

O bundle habilita: launch at login (SMAppService), notificações do sistema e consentimento persistente do Keychain. `project.yml` (XcodeGen) existe para quem preferir um `.xcodeproj`.

## Dados: o que é real, o que é estimado

| Fonte | Real | Estimado |
|---|---|---|
| **Probe Anthropic** (opcional, ~1 token/min) — headers `anthropic-ratelimit-unified-*` via token OAuth local do Claude Code | % oficial 5h/7d, resets, status `allowed/warning/rejected`, janela limitante, saúde por modelo | — |
| **Transcripts Claude** `~/.claude/projects/**/*.jsonl` | tokens (input/output/cache), modelo por mensagem, blocos 5h, ritmo horário | custo (tabela pública em `PricingTable.swift`) |
| **Rollouts Codex** `~/.codex/sessions/**` | % exato por janela (classificada por `window_minutes` — planos weekly-only como o Spark são detectados), resets, plano, tokens | custo |
| **Gemini CLI** `~/.gemini/tmp/*/logs.json` | prompts/sessões/última atividade | tokens não existem no disco — o app declara, não inventa |

Token OAuth: `CLAUDE_CODE_OAUTH_TOKEN` → `~/.claude/.credentials.json` → Keychain (prompt de consentimento do macOS). Nunca é logado; nunca sai da máquina exceto para `api.anthropic.com`. Desligável em Settings (budgets manuais viram fallback).

## Personalizar contas de API

1. Abra **Settings → Contas de API**.
2. Clique em **+** e escolha o serviço.
3. Salve a credencial no Keychain ou use **Conectar conta**.
4. Confirme no card a fonte, a janela e o estado da leitura.

O repositório não contém contas predefinidas. Nomes, projetos, chaves, cookies,
histórico e valores pessoais permanecem fora do Git. Veja
[`docs/API_ACCOUNT_MONITORING.md`](docs/API_ACCOUNT_MONITORING.md).

## Novidades da versão 2.0: monitoramento financeiro de APIs

- **Múltiplas contas** — adicione quantas contas quiser, inclusive duas ou mais
  do mesmo provedor, sem compartilhar credenciais entre elas.
- **Leitura financeira uniforme** — cada card separa **Gasto da janela**,
  **Saldo atual** e **Plano mensal**; recarga nunca é classificada como gasto.
- **Fontes verificáveis** — cada valor registra se veio de API oficial, portal
  oficial, configuração manual ou estimativa proporcional do plano.
- **Períodos explícitos** — padrão de 30 dias; Google AI Studio mantém sua
  janela oficial de 28 dias; mês-calendário aparece identificado quando for a
  única janela oferecida pelo provedor.
- **Operação segura** — refresh individual, proteção contra cache antigo,
  sessões web isoladas, diagnóstico sanitizado e conversão USD/BRL pela PTAX
  atual do Banco Central.

Serviços cobertos na 2.0 incluem Anthropic API, OpenAI, DeepSeek, OpenRouter,
Google/Gemini, xAI, ElevenLabs, Firecrawl, twitterapi.io e múltiplos projetos
X/Twitter. Planos web como Claude/Claude Code e ChatGPT aparecem separados do
consumo de API.

## Controle de versão e releases

O projeto usa [Versionamento Semântico](https://semver.org/lang/pt-BR/):

- **MAJOR**: mudança incompatível ou nova geração do produto.
- **MINOR**: funcionalidade compatível.
- **PATCH**: correção compatível.

`VERSION` é a fonte oficial da versão. `Scripts/make-app.sh` lê esse arquivo no
empacotamento; `Resources/Info.plist`, README e CHANGELOG devem acompanhar o
mesmo número. Antes de qualquer publicação:

```bash
./Scripts/check-version.sh
./Scripts/audit-public-release.sh
NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test
```

Toda versão deve adicionar uma entrada no topo de `CHANGELOG.md` com data,
novidades, correções, segurança e validação.

## Arquitetura

```
Providers (plugin) ─▶ UsageSnapshot ─▶ UsageStore (@Observable) ─▶ Notch · MenuBar · Dashboard
      ▲ FileScanCache/actors    ▲ StatusAggregator + ThresholdAlerts + BurnRate (puros, testados)
RefreshScheduler ───────────────┴─▶ SnapshotStore/HistoryStore (JSON, 30d)
```

- **Overlay**: `NSPanel` borderless não-ativante (`.statusBar` level, todos os Spaces, sobre fullscreen) com `hitTest` custom — só a forma visível captura cliques; o resto da janela transparente é click-through.
- **Interações**: monitores locais de `scrollWheel` (paging) e `keyDown` (Esc), haptics em página/pin, `TimelineView` para countdowns vivos.
- **Novo provider** = 1 pasta com parser puro + `UsageProvider` + fixture; a UI se adapta às capacidades declaradas.

## Modelo de precisão (o que é exato, o que é estimado)

**Exato (fonte oficial):**
- Os **percentuais** de quota do Claude vêm dos headers `anthropic-ratelimit-unified-*` da API — são **da conta inteira**: cobrem Claude Code CLI, app Desktop, claude.ai web e mobile. O mesmo vale para os percentuais do Codex (rollouts locais refletem o estado da conta).
- Horários de reset e status (`allowed/warning/rejected`) — idem.

**Contado localmente (alinhado à janela oficial):**
- Tokens e custos do Claude somam **todas** as fontes locais de transcript: CLI (`~/.claude/projects`) **e as sessões de agente do app Desktop** (`~/Library/Application Support/Claude/local-agent-mode-sessions`).
- As somas de sessão/semana usam **a mesma janela do percentual** (início = reset oficial − 5h/7d), não "últimas N horas corridas".
- Sessão do Codex soma **todos os rollouts ativos dentro da janela** (sessões concorrentes não subcontam).

**Margens conhecidas (medidas, não estimadas):**
- Conversas de *chat* (Desktop/web) não geram transcript local → contam no **%**, não nos tokens locais.
- Buckets horários ⇒ fronteira de janela com precisão de ±1h nos tokens (o % não é afetado).
- Duplicatas de retry entre arquivos: **0,18%** de inflação medida nesta base (dedup é por arquivo).
- Custos usam tabela de preços pública (`PricingTable.swift`) — planos por assinatura não faturam por token; trate como ordem de grandeza.

## Limitações conhecidas

- Geometria do notch é inferida (`safeAreaInsets` + auxiliary areas) — sem API oficial; fallback pill cobre mudanças da Apple.
- Custos são estimativas por tabela pública; planos por assinatura não faturam por token.
- Assinatura ad-hoc: o consentimento do Keychain re-pergunta a cada rebuild.
  Configure `NOTCHAGENT_SIGN_IDENTITY` para manter uma identidade estável.
- `Limited` na página MODELS reflete o rate-limit unificado da conta no momento da sonda, não indisponibilidade do modelo em si.

## Checklist de comercialização

- [x] NotchAgent 2.0 · monitoramento financeiro de APIs · suíte automatizada
- [x] .app empacotado com ícone + launch-at-login + notificações
- [ ] Conta Apple Developer → assinar com Developer ID + `notarytool` + staple *(requer credenciais do dono)*
- [ ] DMG (`create-dmg`) e/ou cask Homebrew apontando para GitHub Releases
- [ ] Auto-update (Sparkle) — pós-lançamento
- [ ] Site/landing + licenciamento (Paddle/Lemon Squeezy) — decisão de negócio

## Observabilidade

```bash
/usr/bin/log stream --predicate 'subsystem == "br.com.lfrprojects.notchagent"' --level debug
```
