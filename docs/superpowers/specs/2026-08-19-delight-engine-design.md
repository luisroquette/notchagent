# Delight Engine — Design (camada "delight sem anúncio")

**Status:** aprovado em brainstorm (19/08/2026). Decisões do usuário marcadas com ✅.

## Objetivo

Uma camada de micro-reações no painel — mascote com vida própria, momentos
de celebração, som/háptica sutil e tinta de fundo por hora do dia — disparadas
em "momentos oportunos". Regra de ouro: **nunca interromper, nunca piscar,
nunca anunciar**.

## Princípios (decisões do usuário)

- ✅ As 4 direções formam um **leque de reações para momentos diversos** — não uma feature única.
- ✅ Gatilhos **mistos**: catálogo de momentos fixos + chance (~20%) de gesto aleatório ao expandir.
- ✅ O mascote **não é um tamagotchi pré-programado** — tem agência simulada: estado interno evolui sozinho, eventos apenas influenciam, ele pode ignorar ou agir por conta própria.
- ✅ **Memória persistente** entre sessões (humor/energia/afeto sobrevivem ao fechamento).
- ✅ **Um toggle mestre** nas configurações ("Efeitos e reações do painel"). Desligado = painel sóbrio, sem gesto, som, háptica ou tinta.
- ✅ Arquitetura escolhida: **Abordagem A — Motor de Humor com animação procedural** (zero asset novo; sprites existentes animados por transformação).

## Arquitetura

```
MascotMind (observable, MainActor, tick 60s)
 ├─ MascotMindCore   — lógica pura: evolve, nudge, escolha de gesto (RNG injetável)
 ├─ DelightCatalog   — momento → peso + gestos elegíveis + cooldowns + regra da teimosia
 ├─ DelightSignals   — detectores puros: reset de quota, meia-noite, primeiro expand do dia, tinta por hora
 ├─ MascotMindPersistence — JSON em Application Support (load corrupto → estado fresco)
 ├─ MascotPuppetView — transformações procedurais sobre o sprite (squash/tilt/hop/…)
 ├─ DelightSounds    — ticks sintetizados (AVAudioEngine) + háptica nativa
 └─ TimeTintView     — gradiente por hora do dia (só com clima desligado)
```

## Catálogo de momentos

| Momento | Peso | Reação típica (não garantida — ele decide) |
|---|---|---|
| quotaReset | 0.9 | aceno / pulinho |
| firstExpandOfDay | 0.8 | olha o cursor / inclina a cabeça |
| peakPassed | 0.7 | respiro / piscada |
| midnight | 0.6 | bocejo + "z z z" / piscada sonolenta |
| idleThirtySeconds | 0.4 | olha o cursor / piscada |
| randomExpand (~20%) | 0.3 | piscada / pulinho / tilt / espreguiçar |

## Regras do motor (testáveis)

- **Energia** decai devagar com ociosidade; **afeto** sobe com uso diário, cai com ausência.
- **Humor derivado**: burn alto → `alert`; energia < 0.3 → `sleepy`; energia > 0.7 e afeto > 0.6 → `curious`; senão `calm`.
- **Vontade própria**: chance de ignorar um nudge = `0.35 − 0.25·afeto` (mín. 0.05), amortecida pelo peso do evento. **Teimosia**: 2 ignoradas seguidas → a 3ª reação é forçada.
- **Cooldown**: 1 reação a cada 90s; o mesmo gesto nunca se repete consecutivamente.
- **Iniciativa própria**: no tick, chance `0.15·energia` de um gesto espontâneo (piscar, olhar pro lado).
- **Acessibilidade**: Reduce Motion congela a animação; VoiceOver silencia o som.

## Não-objetivos

- Sem novos sprites/quadros gerados (futuro upgrade: Abordagem B, sem mudar o motor).
- Sem som com arquivos de áudio — tudo sintetizado.
- Sem reação quando o painel está fechado (tick pausa com ele).
