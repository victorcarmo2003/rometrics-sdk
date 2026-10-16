# Changelog

## 0.3.1

**SDK**
- Falha de envio agora aparece no Output mesmo sem `debug`: na primeira falha da sequência (`send failed: <motivo> ...`) e quando o SDK pausa os envios (`5 consecutive send failures (<motivo>); pausing for 60s`). A mensagem traz o motivo (ex.: `ConnectFail`, `HTTP 503`) e o endpoint em uso, nunca a chave.
- Erro de conexão no endpoint padrão diz explicitamente para passar `endpoint` no `RoMetrics.init`.
- Também no Wally: `victorcarmo2003/rometrics@0.3.1`.

## 0.3.0

**SDK**
- `RoMetrics.trackReceipt(receiptInfo)`: registra a venda de um developer product quando o seu jogo já tem o próprio `ProcessReceipt` (chame logo antes de devolver `PurchaseGranted`). Alternativa ao `wrapProcessReceipt`.
- O `ProcessReceipt` tem um dono só (a última atribuição vence). Se um produto for comprado e nenhum callback embrulhado nem `trackReceipt` registrar em 30 s, o SDK avisa uma vez no Output.
- Um handler que devolve `nil` ou um valor que não é decisão agora gera aviso e devolve `NotProcessedYet`.
- Também no Wally: `victorcarmo2003/rometrics@0.3.0`.

**Plugin do Studio**
- Visual novo e navegação por tarefa: **Início**, **Medir** ("o que você quer medir?" com assistentes que geram a linha de código), **Vendas** (acha quem atribui o `ProcessReceipt` e embrulha com 1 clique, com prévia e Ctrl+Z), **Eventos** e **Ajustes**.
- **Ajustes › Testar com o site**: cole o código gerado no painel (Configurações › Jogos › Testar conexão). O painel confere o jogo aberto, o SDK, o script de setup e o endereço, e espera o primeiro evento.
- **Ajustes › Enviar eventos de teste**: manda os eventos custom do registro (marcados como teste) sem precisar dar Play, para ver como chegam no painel.
- Ferramentas avançadas (marcar objeto sem código, editor de funis, conferir problemas) continuam disponíveis.

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
