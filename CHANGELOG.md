# Changelog

## 2.0.0 — 2026-07-28 (atualizado em 2026-07-30)

Segunda geração do NotchAgent, agora também voltada ao monitoramento financeiro
de contas de API.

### Descontinuações

- O companion iOS/watchOS "AgentMeter" foi descontinuado e removido do
  repositório. O monitoramento financeiro de contas de API segue só no app Mac.

### Monitoramento de APIs

- Cadastro genérico de múltiplas contas por provedor, com credenciais isoladas
  no macOS Keychain e sessões web separadas por conta.
- Dashboard financeiro em BRL com **Gasto da janela**, **Saldo atual** e
  **Plano mensal**, sem misturar recargas, assinaturas e quotas.
- Integrações para Anthropic API, OpenAI, DeepSeek, OpenRouter, Google/Gemini,
  xAI, ElevenLabs, Firecrawl, twitterapi.io e múltiplos projetos X/Twitter.
- Assinaturas Claude/Claude Code, ChatGPT, Google AI e Firecrawl separadas do
  consumo faturado das APIs.

### Precisão e atualização

- Origem registrada por campo: API oficial, portal oficial, valor manual ou
  estimativa proporcional.
- Reconciliação entre API e portal com tolerâncias explícitas; divergências
  deixam o card parcial em vez de exibir um valor como confirmado.
- Janela padrão de 30 dias, Google em 28 dias oficiais e mês-calendário
  identificado quando exigido pelo provedor.
- Valores oficiais em BRL preservados sem reconversão; USD convertido pela
  cotação PTAX atual do Banco Central.
- Refresh individual por card, invalidação forçada de cache e proteção contra
  respostas antigas sobrescrevendo leituras novas.
- Total consumido de 30 dias explica no card quando uma conta fica de fora por
  dividir billing scope com outra já contada, em vez de sumir sem explicação.
- Estimativa de custo por modelo não reconhecido na tabela de preços deixou de
  contar como US$0 verificado — fica de fora da estimativa, não zerado.

### Interface e operação

- Lista rolável com todos os provedores, detalhes expansíveis e reordenação por
  arrastar.
- Estados visíveis: atualizando, atualizado, desatualizado, parcial e erro.
- Correção do gesto vertical que mudava indevidamente a página do notch.

### Segurança e distribuição

- Diagnóstico exportável sem credenciais, cookies, nomes, IDs ou valores.
- Auditoria pública, hook `pre-push` e workflow de CI bloqueiam padrões de
  segredo e identificadores pessoais.
- Assinatura do bundle configurável por ambiente, sem certificado pessoal
  fixado no código.
- `graphify-out` removido do Git por replicar código e dados gerados.

### Qualidade

- 206 testes automatizados aprovados, incluindo integridade financeira, cache,
  persistência, segurança, scroll e E2E somente leitura das contas configuradas.
- Testes e builds de release executados com probes pagos desativados.

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
