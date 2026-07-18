# Design System

## Direction

Controle operacional civil, dark-first: composição editorial assimétrica, telemetria integrada ao canvas e uma única faixa clara de alto contraste. Referências 8-bit conectam o iPhone ao AgentMeter: Desktop Bar em momentos pequenos e funcionais. A identidade aeroespacial vem de escala, precisão, contraste e espaço negativo — nunca de fantasia, logotipos ou espaçonaves. A arquitetura visual da tela inicial foi gerada e refinada no Google Stitch antes da tradução para SwiftUI.

## Color

- Canvas: `#000000` no escuro; cinza frio quase branco no tema claro.
- Ink escuro: `#F0F0FA`, alinhado ao branco frio da referência.
- Ink: texto primário do sistema para contraste máximo.
- Surface: `#05070A` e Elevated `#0B0E12` no escuro.
- Signal Blue: `#2D8CFF`, reservado para ação primária, progresso e seleção.
- Nominal Green: `#35D49A`, reservado para estados saudáveis e sincronizados.
- Warning Amber: `#FFB547`, reservado para cobrança próxima e atenção.
- Critical Red: `#FF5D63`, reservado para falhas e ações destrutivas.
- Provider colors: apenas em identificadores pequenos de Claude, ChatGPT e Gemini.

## Typography

- D-DIN para texto e rótulos; D-DIN Bold para marca, títulos e ações.
- Roboto Mono para valores de telemetria, datas curtas e métricas financeiras.
- Títulos operacionais em caixa alta, tracking próximo de `0.02em` e entrelinha compacta, seguindo a configuração observada no site oficial da SpaceX.
- Hierarquia compacta: 46 pt apenas no instrumento central; 15–20 pt para ações e corpo. Fontes customizadas escalam com Dynamic Type; apenas micro-rótulos estruturais usam tamanho fixo para preservar o cockpit no modo de acessibilidade.

## Spacing

Escala de 4 pt: 4, 8, 12, 16, 20, 24, 32, 48. Margem horizontal principal de 16 pt. Áreas de toque de no mínimo 44 pt.

## Shape

- Painéis e controles funcionais: raio 4 pt.
- Cápsulas: somente status e filtros.
- Linhas finas e agrupamento substituem cartões aninhados.

## Components

- Cost Hero: custo mensal é a resposta dominante, alinhada à esquerda e sem contêiner decorativo.
- Telemetry Manifest: cobertura, origem e sincronização aparecem em uma faixa linear sem cartões.
- Boarding Pass: próximo faturamento ocupa a única grande superfície clara e conduz diretamente ao detalhe.
- Provider Manifest: provedores formam uma lista operacional contínua com divisores hairline, nunca uma grade de cartões.
- Pixel Companion: mascote procedural 8-bit usado como indicador de saúde e configuração.
- Segmented Gauge: cada bloco representa um item real; nunca funciona como decoração ou progresso fictício.
- Status Chip: ícone, estado e texto curto; cor semântica.
- Provider Telemetry: linhas verticais com status, valor e disclosure.
- Event Rail: próximo evento real em uma única linha operacional, com indicação temporal imediatamente escaneável.
- Command Bar: navegação inferior apenas para destinos funcionais.
- Pixel Rail: trilho segmentado marca a seleção atual sem alterar o padrão nativo de navegação.
- Primary Action: preenchimento Signal Blue, rótulo direto e feedback de pressão.
- Section Header: rótulo operacional monoespaçado, usado apenas em grupos funcionais.

## Motion

A tela principal aparece completa, sem coreografia de carregamento. Estados locais permanecem entre 150–240 ms, sem mola. Redução de movimento remove transformações e preserva mudanças instantâneas ou crossfade.

## Content

Português claro e humano. Termos técnicos só quando aumentam confiança. “Oficial”, “informado por você” e “estimado” devem aparecer junto ao dado correspondente.
