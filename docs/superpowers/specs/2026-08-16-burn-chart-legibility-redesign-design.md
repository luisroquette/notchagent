# Burn Chart — Legibilidade das Linhas Multi-Modelo

## Contexto

A feature de projeção multi-modelo (spec `2026-08-15-burn-chart-multi-model-projection-design.md`)
foi ao ar e testada ao vivo. Achado real: as 4 cores escolhidas na primeira
rodada nunca foram validadas cientificamente — rodadas pelo validador de
contraste da skill `dataviz` (ΔE em OKLab), Sonnet e Haiku ficam a ΔE 12 de
distância, abaixo do piso de 15 pra qualquer pessoa com visão normal
distinguir duas cores adjacentes. Isso bate exatamente com o relato do
usuário ("não consigo enxergar nada") — não é regressão de dado, é palheta
mal calibrada.

Além disso, o painel (fixo 660×430, compartilhado com todas as páginas do
app — fora de escopo redimensionar) deixa a legenda em linha separada +
legenda estática comendo espaço vertical que poderia ir pro canvas do
gráfico.

## Design

### 1. Paleta — substitui `Theme.modelHaiku/modelSonnet/modelOpus/modelFable`

Validada com `dataviz/scripts/validate_palette.js` junto do coral existente
(5 cores simultâneas no pior caso: destaque + 3 alternativas):

| Modelo | Dark (float RGB) | Light (float RGB) | Hex dark / light |
|---|---|---|---|
| Haiku | (0.224, 0.529, 0.898) | (0.165, 0.471, 0.839) | `#3987E5` / `#2A78D6` |
| Sonnet | (0.098, 0.620, 0.439) | (0.106, 0.686, 0.478) | `#199E70` / `#1BAF7A` |
| Opus | (0.565, 0.522, 0.914) | (0.290, 0.227, 0.655) | `#9085E9` / `#4A3AA7` |
| Fable | (0.835, 0.318, 0.506) | (0.910, 0.482, 0.643) | `#D55181` / `#E87BA4` |

Pior par: ΔE 16.0 (dark, deutan) / 19.7 (dark, normal-vision) — folga
confortável acima do piso de 15. Modo claro: `ALL CHECKS PASS` (só WARN de
contraste em 2 cores contra o fundo claro — mitigado pelas labels diretas
sempre visíveis do item 2, que é exatamente a "relief rule" da skill:
"ship visible direct labels", não precisa de texto colorido).

O coral (`Theme.coral`, destaque do modelo atual) continua igual — é
identidade de marca já usada no app inteiro, fora de escopo mudar aqui.

### 2. Rótulos diretos na ponta da linha, substituindo a linha de legenda

Remove a `HStack` de legenda separada (`● SONNET ● HAIKU...`) e a função
`legendDot`. Cada linha — as 3 alternativas E a linha principal (coral) —
ganha o nome do modelo no ponto onde ela já está sendo olhada:

- **Alternativas:** nome + ponto colorido logo depois do fim de cada linha
  tracejada (mesmo p.onto onde `alternatePolyline` já para de desenhar).
  Texto sempre em `Theme.textFaint` (nunca na cor da série — regra do
  design system: "text never wears the data color"), só o ponto carrega a
  cor de identidade.
- **Linha principal (coral):** o rótulo "NOW" existente passa a incluir o
  nome do modelo em destaque (`"NOW · SONNET"`) — reaproveita o espaço já
  reservado, não é uma marca nova.
- **Anti-colisão:** quando duas labels de alternativas caem muito perto
  verticalmente (linhas com fator de preço próximo), empurra a de baixo
  pra baixo em passos fixos até abrir um vão mínimo — função pura, testável
  isoladamente (mesmo padrão de `BurnRate`/`ModelProjection`: lógica sem
  UI fica em função testada; só o `Canvas` em si fica sem teste unitário,
  como já é convenção neste arquivo).

Isso substitui — não soma — o antigo par (legenda em linha + linhas do
gráfico já rotuladas visualmente na origem): a identidade nunca depende só
de cor, só que o texto mora no traço em vez de numa lista separada embaixo.
Desvio consciente da leitura mais literal da regra "legenda sempre presente
pra 2+ séries" da skill `dataviz` — com no máximo 4 séries e rótulo sempre
visível (não só no hover) grudado em cada marca, o requisito por trás da
regra (nunca depender só de cor) continua satisfeito; só a caixa de legenda
separada é que sai, porque neste widget compacto ela custa mais espaço do
que entrega.

Libera ~20px de altura vertical pro canvas do gráfico.

### 3. Legenda estática mais curta

`"SOLID = REAL USAGE · DOTTED = PROJECTION AT CURRENT PACE"` (58 caracteres)
vira `"SOLID = REAL · DASHED = PROJECTED"` (34 caracteres) — mesma
informação, mais compacta.

### 4. Linhas mais grossas

Linhas alternativas: `lineWidth` 1 → 2 (padrão de linha do design system,
`dataviz/references/marks-and-anatomy.md`: "Line: 2px"). Diferenciação da
linha principal continua por traço sólido-vs-tracejado e cor, não por
espessura — 1px estava efetivamente invisível no painel físico.

## Fora de escopo

- Redimensionar o painel (660×430 é compartilhado com todas as páginas).
- Réplica pro Codex (GPT 5.6 Sol/Terra/Luna) — combinado que fica pra depois.
- Mudar a cor do coral em si (identidade de marca já estabelecida).
