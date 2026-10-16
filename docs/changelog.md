# Changelog

## 0.1.0

Primeira versão pública.

- SDK Luau server-side: `init`, `wrapProcessReceipt`, API compatível com `AnalyticsService` (`LogCustomEvent`, `LogEconomyEvent`, `LogFunnelStepEvent`, `LogOnboardingFunnelStepEvent`, `LogProgressionEvent`), `track` e `flush`.
- Rastreio automático de servidores (heartbeat/CCU), entradas e saídas, país, Premium, origem (`launchData`/teleport), Game Passes e plataforma do jogador.
- Eventos sem código por tag `RoMetrics` + atributos `RM_*` (Touched, ProximityPrompt, ClickDetector, Activated).
- Fila com lotes, gzip, backoff, circuit breaker e flush no `BindToClose`.
- Plugin do Studio: registro de eventos, marcação por tags, snippets, editor de funis, validação e configuração.
