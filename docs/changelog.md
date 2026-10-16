# Changelog

## 0.2.0

Plugin do Studio redesenhado. O SDK não mudou (continua igual ao 0.1.0).

- Nova aba **Início** com checklist: instala o SDK do GitHub em 1 clique (última release), testa o endpoint, lembra do Secret e cria o script de setup.
- Navegação em barra lateral agrupada (Começar, Eventos, Conferir), logo do RoMetrics e selo de status do SDK no topo.
- Aba Snippets virou **Código**: sem script selecionado, o código vai para o script de setup ou para um Script novo; avisa quando o SDK não está no place.
- Setas e ícones que viravam quadradinhos na fonte do Studio foram trocados.

## 0.1.0

Primeira versão pública. Também no Wally: `victorcarmo2003/rometrics@0.1.0`.

- SDK Luau server-side: `init`, `wrapProcessReceipt`, API compatível com `AnalyticsService` (`LogCustomEvent`, `LogEconomyEvent`, `LogFunnelStepEvent`, `LogOnboardingFunnelStepEvent`, `LogProgressionEvent`), `track` e `flush`.
- Rastreio automático de servidores (heartbeat/CCU), entradas e saídas, país, Premium, origem (`launchData`/teleport), Game Passes e plataforma do jogador.
- Eventos sem código por tag `RoMetrics` + atributos `RM_*` (Touched, ProximityPrompt, ClickDetector, Activated).
- Fila com lotes, gzip, backoff, circuit breaker e flush no `BindToClose`.
- Plugin do Studio: registro de eventos, marcação por tags, snippets, editor de funis, validação e configuração.
