# Weather Ambience — Design Spec

**Date:** 2026-08-18
**Status:** Approved (3 sections, user-approved)

**Goal:** Uma camada de ambiente na página Now do painel expandido do NotchAgent: o fundo reage ao clima local de forma sutil ("só quem presta muita atenção percebe") e uma linha discreta no topo mostra relógio local + temperatura. Sem anúncio da feature em lugar nenhum da UI.

**Approach (A1):** Clima real via Open-Meteo (grátis, sem API key). Localização via geo-IP uma única vez na primeira execução, com override manual de cidade nas Settings. Zero prompt de permissão, zero custo, offline-safe.

**Tech Stack:** SwiftUI, Canvas + TimelineView, Open-Meteo API, ipwho.is (geo-IP), XCTest (Swift 6).

## Global Constraints

- **Nunca degradar o painel principal:** qualquer falha (rede, geocoding, parse, rate limit) → estado `.unavailable` → fundo neutro (como hoje) e temperatura some. O relógio local permanece — hora não depende de rede. Toggle desligado é diferente: desliga TUDO, inclusive o relógio.
- **Zero prompt de permissão** — nada de CoreLocation, nada de WeatherKit (conta developer paga).
- **Zero custo** — Open-Meteo e ipwho.is são gratuitos e sem key. Uma chamada de cada por ciclo de 30 min.
- **Sutileza absoluta:** nenhum elemento do fundo passa de alpha 0.16. Cards e números são sempre o protagonista.
- **CPU zero fora da página Now:** animação só roda com o painel expandido na página 0; `TimelineView(.animation(paused:))` caso contrário.
- **Reduce Motion:** fundo vira estático (só gradiente), sem partículas.
- **Copy em inglês** (padrão da UI): sem textos novos além de "Ambiente"/"Weather ambience" nas Settings.
- **Local-first:** cache em UserDefaults (struct pequena). Nada de backend próprio.

---

## Architecture

### Componentes novos

1. **`WeatherCondition`** (`Sources/NotchAgent/Core/Models/Weather.swift`, enum puro, Codable, Equatable)
   - Cases: `clear`, `partlyCloudy`, `cloudy`, `rain`, `storm`, `snow`
   - `static func from(wmoCode: Int) -> WeatherCondition?` — tabela WMO → enum, função pura testada. Desconhecido → nil.

2. **`WeatherSnapshot`** (mesmo arquivo, struct Codable, Equatable)
   - `condition: WeatherCondition`, `temperatureC: Double`, `isDay: Bool`, `city: String`, `capturedAt: Date`.

3. **`WeatherService`** (`Sources/NotchAgent/Core/Services/WeatherService.swift`, `actor`)
   - `func fetch(lat: Double, lon: Double) async throws -> WeatherSnapshot` — GET ao Open-Meteo `https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..&current=temperature_2m,weather_code,is_day&timezone=auto`, parse mínimo.
   - `func geocode(city: String) async throws -> (lat: Double, lon: Double, name: String)` — GET `https://geocoding-api.open-meteo.com/v1/search?name=..&count=1&language=pt&format=json`.
   - Sem estado. Erros de rede/parse propagam como `throw` — quem decide o fallback é o store.

4. **`WeatherStore`** (`Sources/NotchAgent/Core/Services/WeatherStore.swift`, `@MainActor @Observable`, registrado no `AppEnvironment` ao lado dos demais serviços)
   - `enum Phase: Equatable { case fresh(WeatherSnapshot), stale, unavailable }`
   - `var phase: Phase` — a UI lê só isso.
   - `func refreshIfNeeded() async`:
     1. Lê cache (UserDefaults, key `weather.snapshot`). Fresco (< 30 min) → `.fresh`, fim.
     2. Resolve local: `settings.weatherCity` (manual, via geocoding) OU lat/lon persistidos (`weather.lat/lon`) OU geo-IP (ipwho.is, `https://ipwho.is/` → latitude/longitude/city) — **uma única vez na vida do app**: resultado persistido em `weather.lat/lon/city`.
     3. `WeatherService.fetch` → snapshot → cache + `.fresh`.
     4. Qualquer throw → `.unavailable` (cache velho é descartado da tela, não exibido como fresco).
   - `func start() async` — loop de 30 min (`Task.sleep`) + primeira execução imediata. Cancela quando `settings.weatherEnabled == false`.
   - Toggle `weatherEnabled == false` → phase `.unavailable` e nada roda.

5. **AppSettings** (`Sources/NotchAgent/Core/Models/AppSettings.swift`, campos novos)
   - `weatherEnabled: Bool` (default `true`)
   - `weatherCity: String?` (override manual; nil = automático)
   - `weatherLat: Double?`, `weatherLon: Double?`, `weatherCityResolved: String?` (persistidos após a 1ª resolução; limpar cidade manual NÃO apaga — voltar ao automático usa os persistidos, sem novo geo-IP)
   - Todos com CodingKeys e decode defaults (`?? true` / `?? nil`) para snapshots antigos.

### Fluxo de dados

```
launch → AppEnvironment.startWeather() → WeatherStore.refreshIfNeeded()
   cache fresco (<30min)  → .fresh → fundo + header de clima
   velho/sem cache        → cidade manual (geocoding) OU persistida OU geo-IP (1ª vez)
                          → Open-Meteo → cache + .fresh
   qualquer throw         → .unavailable → página Now idêntica à de hoje
```

---

## Visual Layer

### `WeatherAmbienceView` (fundo da página Now, `Canvas` + `TimelineView` em ZStack atrás do conteúdo)

| Condição | Efeito |
|---|---|
| `rain` | ~24 traços diagonais finos caindo, alpha 0.10–0.16, velocidades/larguras variadas |
| `storm` | Chuva mais grossa + flash ocasional de fundo (alpha ≤ 0.06, aleatório, ~1 a cada 3-8s) |
| `cloudy` | Gradiente acinzentado estático (sem partícula) |
| `clear` + dia | Glow âmbar radial no canto superior (alpha ~0.05) |
| `clear` + noite | Véu azul-escuro leve (não escurece os números) |
| `snow` | Partículas brancas lentas, alpha ≤ 0.14 |
| `.unavailable` / `stale` | Fundo neutro (padrão atual) |

- A animação roda SÓ com painel expandido na página 0; caso contrário `TimelineView(.animation(paused: true))` — custo zero de CPU fora da Now.
- `@Environment(\.accessibilityReduceMotion)`: true → sem partículas, só gradiente.

### `WeatherHeaderView` (linha fina no topo da página Now, acima dos cards)

- Esquerda: relógio local HH:MM (fonte numeral pequena, monospacedDigit) — **sempre visível**, não depende de rede.
- Direita (só com snapshot fresco): ícone SF Symbol da condição + temperatura `"24°"` (arredondada, monospaced).
- Sem condição → direita vazia.
- Cores 100% do `Theme` existente.

### Settings (Section "Ambiente")

- Toggle **"Weather ambience"** (default on). Desligado = nada da feature roda (fundo neutro, sem header, sem rede, sem loop).
- Campo **"Cidade manual (opcional)"** — TextField + botão limpar (volta ao automático).

---

## Error Handling

- Regra única: **qualquer throw → `.unavailable`**. Não há retry loop agressivo (próximo ciclo de 30 min tenta de novo naturalmente).
- Geo-IP falhou E sem cidade manual → `.unavailable` (a feature simplesmente não existe até o usuário configurar cidade).
- Geocoding de cidade manual falhou → `.unavailable`, cidade digitada é preservada no settings.
- Cache corrompido (decode falhou) → descartar silenciosamente e refazer fetch.

## Testing

1. **WMO mapping** — tabela completa (0,1,2,3 → clear/partlyCloudy/cloudy/…; 51-67 → rain; 71-77,85,86 → snow; 80-82 → rain; 95,96,99 → storm) + código desconhecido → nil.
2. **`WeatherSnapshot` decode** — fixture do JSON real do Open-Meteo.
3. **`WeatherStore`** (com `WeatherService` mockável via protocolo):
   - cache fresco não refaz fetch
   - cache velho refaz
   - cidade manual vence lat/lon persistido e geo-IP
   - falha de rede → `.unavailable`
   - `weatherEnabled == false` → `.unavailable` sem chamada
4. **Formatação** — relógio HH:MM local, temperatura arredondada, ícone por condição (funções puras).

## Out of Scope (YAGNI)

- min/max do dia, previsão de 7 dias, alertas de tempestade
- animação no notch compacto
- WeatherKit / CoreLocation
- Unidades configuráveis (sempre °C)
