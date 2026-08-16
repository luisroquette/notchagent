# Burn Chart — Projeção Multi-Modelo (Claude)

## Contexto

O `BurnChartView` atual (`BURN · WILL THE 5H SESSION LAST?`) mostra uma única
linha: sólida = % da quota realmente consumida na janela de 5h, tracejada =
projeção no ritmo atual até o reset. O usuário quer responder "se eu tivesse
usado outro modelo, quando eu teria estourado a quota?" — comparando o modelo
que está de fato usando agora contra os outros 3 tiers da Claude (Haiku,
Sonnet, Opus, Fable) no mesmo gráfico, com o modelo vigente em destaque e os
demais em linhas mais discretas.

Fora de escopo: réplica para o Codex (GPT 5.6 Sol/Terra/Luna) — fica para uma
spec futura; hoje `PricingTable` só tem um catch-all genérico `"gpt-5"`, então
precisaria da mesma correção de preços antes de fazer sentido.

## Pré-requisito: `PricingTable` desatualizada

`claude-opus` e `claude-fable` caem hoje no mesmo entry catch-all
(`input:15, output:75, cacheWrite:18.75, cacheRead:1.5` — preço do Opus
pré-5). Isso deixa Opus 5 e Fable 5 com o **mesmo custo estimado**, quando na
realidade Fable é mais caro que Opus (confirmado: Opus 5 = $5/$25 por MTok,
Fable 5 = $10/$50 por MTok). Sem esse fix, as 3 linhas alternativas do
gráfico sairiam com Opus e Fable sobrepostas — o bug teria efeito visível
direto na feature nova, então entra como pré-requisito.

Fix: adicionar entries específicos `"claude-opus-5"` e `"claude-fable-5"`
antes dos catch-alls genéricos (`entries.first { hasPrefix }` respeita ordem
— mais específico primeiro), seguindo a mesma proporção cache-write/cache-read
(1.25x / 0.1x do input) já usada em todos os outros entries da tabela.

## Design

### 1. Fonte de dados: tokens por modelo dentro da janela de 5h

Hoje `UsageSnapshot.modelBreakdown` já existe, mas cobre o lookback de 8 dias
inteiro (não a janela de 5h) e só guarda `tokens: Int` (total, sem quebra
input/output/cache) — não dá pra recalcular custo hipotético de outro modelo
com isso.

Novo campo `SessionUsage.modelTokens: [String: TokenUsage]?` — tokens por
modelo, escopados exatamente à janela de 5h atual. Alimentado por um novo
nível de agregação no parser (`ClaudeFileStat.hourlyByModel: [Date: [String:
TokenUsage]]`, irmão de `hours`/`byModel` que já existem) e um novo
`ClaudeProvider.sumBucketsByModel(...)`, espelhando o `sumBuckets(...)` que
já filtra por janela.

### 2. Modelo em destaque

`ModelProjection.dominantModel(modelTokens:)` — o modelo com mais tokens
gastos em `SessionUsage.modelTokens` dentro da janela atual. Continua
desenhado exatamente como hoje (linha sólida real + tracejado de projeção),
sem nenhuma mudança visual na linha principal.

### 3. Cálculo das 3 linhas alternativas

Sem métrica nova — reaproveita o eixo `% USADO` existente. Para cada modelo
candidato (`ClaudeQuotaProbe.modelRotation`, os 4 tiers já sondados pelo
probe) diferente do dominante:

```
fator = custoUSD(candidato, tokensDaSessão) / custoUSD(dominante, tokensDaSessão)
```

usando `session.tokens` (soma total já existente, independente de qual
modelo gerou cada token — é "se esses tokens tivessem sido gastos 100% no
candidato"). A curva sólida real do gráfico é replotada multiplicada por esse
fator, e a projeção tracejada estende dali com a mesma lógica de burn-rate
(`percentPerHour * fator`) que já existe para a linha principal.

Modelo sem preço conhecido em `PricingTable` (`costUSD` retorna `nil`) →
aquela linha simplesmente não aparece, sem quebrar as outras (mesmo padrão de
"ausência nunca vira zero" já usado no app). Sessão com zero tokens → nenhuma
alternativa é calculada (nada para escalar).

### 4. Renderização

Dentro do `BurnChartView` atual — mesmo `Canvas`, sem view nova. 3 linhas
tracejadas finas (`lineWidth: 1`, mais fina que a principal em `1.6`/`2`), uma
cor fixa por modelo (não por "posição"), para a identidade visual do modelo
ser sempre a mesma independente de qual está em destaque:

| Modelo | Cor |
|---|---|
| Haiku | azul |
| Sonnet | ciano/teal |
| Opus | violeta |
| Fable | rosa/magenta |

O modelo em destaque continua em `Theme.coral` (convenção já usada em todo o
app para "modelo atual" — `PixelGlyph` do model card, gauge principal etc.),
mesmo que ele seja, por exemplo, o Opus — a cor de "modelo atual" e a cor
"fixa daquele modelo" são propositalmente diferentes conceitos.

Legenda: uma linha de texto abaixo do gráfico com um ponto colorido + nome
curto por modelo (reaproveita o mapeamento `"haiku"→"Haiku"` etc. já usado em
`NotchExpandedView.modelFamilies`, mas como uma tabela própria em
`ModelProjection` — a existente é `private` dentro da view e não deve ser
mexida para não arriscar a feature já em produção).

### 5. Edge cases

- **Linha escalada estoura 100% antes de "agora"** (ex.: projetar Fable
  quando a sessão inteira rodou em Haiku) → corta em 100%, não desenha além
  disso (sem marcador "EMPTY" dedicado como a linha principal tem — manter
  simples, é uma linha de contexto, não o dado principal).
- **Modelo sem preço conhecido** → linha omitida silenciosamente.
- **Sessão sem tokens ainda** → nenhuma linha alternativa (chart mostra só o
  estado vazio já existente: "watching your burn...").

### 6. Testes

- Regressão do fix de `PricingTable` (Opus 5 ≠ Fable 5, valores corretos).
- Unit tests de `ModelProjection` (modelo dominante, fatores de preço,
  omissão de modelo desconhecido, sessão vazia) — puros, sem I/O, seguindo o
  padrão já estabelecido por `BurnRate.swift`.
- Teste de parser para `ClaudeFileStat.hourlyByModel`.
- Teste de integração ponta-a-ponta para `SessionUsage.modelTokens` via
  `ClaudeProvider.fetchSnapshot`.
- A matemática de escala dentro do `Canvas` (`alternatePolyline`) segue sem
  teste unitário dedicado — mesmo padrão já usado pelas funções irmãs
  `polyline`/`interpolate` do próprio `BurnChartView`, que também não têm
  cobertura de XCTest (view de desenho, verificação é visual/manual).

## Fora de escopo desta spec

- Réplica para o Codex (GPT 5.6 Sol/Terra/Luna).
- Toggle de ligar/desligar linhas individualmente — as 3 alternativas são
  sempre mostradas (quando o preço é conhecido).
