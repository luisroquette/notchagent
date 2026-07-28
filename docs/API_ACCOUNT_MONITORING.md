# Monitoramento financeiro de APIs

O NotchAgent monitora somente contas ativadas em **Settings → Contas de API**.
Credenciais ficam no macOS Keychain. Preferências, snapshots, diagnósticos e
logs não armazenam chaves, tokens, cookies, IDs de conta ou valores secretos.

## Modelo financeiro

Cada card mantém campos independentes. Um campo ausente continua ausente:

- **Gasto da janela**: consumo cobrado no período oficial indicado no card.
- **Saldo atual**: crédito disponível agora; recargas não são classificadas
  como gasto.
- **Plano mensal**: preço recorrente confirmado pelo provedor ou pelo portal.
- **Recarga**: crédito comprado, separado do consumo.
- **Quota**: unidade nativa do serviço. Uma conversão para reais só aparece
  como **estimativa proporcional**, nunca como valor oficial.

A janela padrão é **30 dias corridos**. Google AI Studio é a exceção explícita:
o portal oficial fornece **28 dias**, preservados no card. O NotchAgent não soma
períodos diferentes em um único total.

Valores oficiais já publicados em reais, como Google AI Studio, permanecem em
BRL. Valores oficiais em USD usam a cotação USD/BRL atual, com fonte e horário
registrados; a cotação não é hardcoded.

## Contas e fontes

| Conta | Fonte oficial preferida | Resultado |
| --- | --- | --- |
| Anthropic API | Console Anthropic conectado | gasto, saldo/créditos e janela disponíveis no portal |
| OpenAI API | Usage/Costs + Billing conectados | gasto em 30 dias e saldo atual |
| DeepSeek | API de saldo + portal conectado | gasto em 30 dias e saldo atual |
| OpenRouter | API de créditos + portal conectado | gasto em 30 dias e saldo atual |
| Google / Gemini | Google AI Studio conectado | gasto oficial em BRL por 28 dias; saldo somente se o provedor informar |
| xAI / Grok | Management API/portal | gasto e saldo quando expostos pela conta |
| ElevenLabs | API de assinatura | quota, uso, reset e plano |
| Firecrawl | API de créditos | quota, uso, reset e plano; saldo negativo vira zero + excedente |
| twitterapi.io | API de créditos | quota, uso e saldo equivalente quando o plano é conhecido |
| X / Twitter (cada conta) | Console X conectado | consumo, recargas e saldo, sem misturar projetos |
| Endpoint personalizado | HTTPS somente leitura | apenas campos declarados pelo contrato |

Assinaturas pessoais, como Claude/Claude Code e ChatGPT, ficam em
**Assinaturas conectadas** e não contam como consumo de API.

## Integridade e atualização

Cada valor guarda sua origem: **API oficial**, **portal oficial**, **configuração
manual** ou **estimativa derivada**. Quando API e portal informam o mesmo campo,
o NotchAgent compara as fontes usando tolerância de 0,02 USD, 0,10 BRL ou uma
unidade de quota. Divergências deixam o card parcial e aparecem no detalhe.

O refresh periódico usa cache de 15 minutos. **Refresh global**, refresh
individual do card, conclusão de login e desconexão invalidam o cache antes da
nova leitura. Gerações de atualização impedem uma resposta antiga de
sobrescrever dados mais novos.

Estados visíveis por card:

- **Atualizando**
- **Atualizado**
- **Desatualizado**
- **Erro**, com a causa sanitizada

## Segurança e diagnóstico

Conexões por portal usam um perfil WebKit isolado por conta. Desconectar remove
somente a sessão daquele perfil. O diagnóstico exportável contém estados,
fontes e janelas, mas remove credenciais, cookies, identificadores, rótulos,
mensagens livres e valores financeiros.

Testes E2E de integridade são somente leitura. Use:

```bash
NOTCHAGENT_DISABLE_PAID_PROBES=1 \
NOTCHAGENT_LIVE_E2E=1 \
swift test --filter testLiveE2EAccountMonitoringWhenExplicitlyEnabled
```

Essa execução não chama modelos pagos Anthropic, OpenAI, Gemini ou OpenRouter.

## Endpoint personalizado

O endpoint HTTPS deve aceitar `Authorization: Bearer` e retornar:

```json
{
  "used_percent": 42,
  "resets_at": "2026-08-01T00:00:00Z",
  "note": "opcional"
}
```

`remaining_percent` pode substituir `used_percent`. Campos desconhecidos são
ignorados.
