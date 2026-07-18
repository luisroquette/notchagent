---
type: "query"
date: "2026-07-17T22:37:06.982997+00:00"
question: "Compare a confianca do estimador iOS com o produto atual do MacBook"
contributor: "graphify"
outcome: "useful"
source_nodes: ["ClaudeQuotaProbe", "ClaudeProvider", "CodexProvider", "CodexRolloutParser", "GeminiProvider", "BurnRate"]
---

# Q: Compare a confianca do estimador iOS com o produto atual do MacBook

## Answer

Expanded via graph vocab: [quota, probe, codex, rollout, gemini, burn, estimate, usage, percent, window]. Current Mac quota confidence is roughly 95-99 percent for Claude when its authoritative header probe is active, and 98-100 percent for Codex because local rollout events carry official percentages and reset times. Claude fallback token budgets are only an estimate, around 40-60 percent. Gemini quota is not shown rather than fabricated. Burn-time forecasts are moderate confidence, around 60-80 percent, and token-based monetary cost estimates around 85-95 percent. A standalone iOS estimator for consumer subscriptions would be around 40-60 percent at best with complete capture and under 30 percent with partial usage.

## Outcome

- Signal: useful

## Source Nodes

- ClaudeQuotaProbe
- ClaudeProvider
- CodexProvider
- CodexRolloutParser
- GeminiProvider
- BurnRate