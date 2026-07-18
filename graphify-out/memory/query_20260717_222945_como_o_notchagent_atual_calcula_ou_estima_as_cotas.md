---
type: "query"
date: "2026-07-17T22:29:45.129944+00:00"
question: "Como o NotchAgent atual calcula ou estima as cotas?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["ClaudeProvider", "ClaudeQuotaProbe", "CodexProvider", "CodexRolloutParser", "GeminiProvider", "BurnRate"]
---

# Q: Como o NotchAgent atual calcula ou estima as cotas?

## Answer

Expanded via graph vocab: [claude, quota, probe, transcript, codex, rollout, rate, window, usage, token, estimate, gemini]. Claude quota is authoritative when the optional one-token probe reads Anthropic 5h and 7d utilization headers; local transcripts provide tokens and estimated cost. Without the probe, percentages use user-configured token budgets or remain hidden. Codex quota is authoritative because rollout JSONL files contain used_percent and reset timestamps. Gemini exposes only local activity, so quota and tokens remain unavailable. Burn rate is a linear projection from recent percent samples; monetary cost uses a pricing table.

## Outcome

- Signal: useful

## Source Nodes

- ClaudeProvider
- ClaudeQuotaProbe
- CodexProvider
- CodexRolloutParser
- GeminiProvider
- BurnRate