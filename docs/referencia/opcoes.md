# Opções do init

| Opção | Tipo | Padrão | Intervalo | Efeito |
|---|---|---|---|---|
| `key` | `Secret \| string` | — | não vazia | chave de ingestão do jogo. Obrigatória |
| `endpoint` | `string` | `"https://ingest.rometrics.app"` | URL `http(s)://` | host do ingest. Barras finais são removidas |
| `flushInterval` | `number` (s) | `10` | 1 – 300 | intervalo entre envios |
| `maxBatchSize` | `number` | `100` | 1 – 500 | eventos por envio. Inteiro |
| `maxQueueSize` | `number` | `5000` | 1 – 100000, ≥ `maxBatchSize` | eventos em memória antes de descartar os mais antigos |
| `heartbeatInterval` | `number` (s) | `30` | 5 – 60 | intervalo do heartbeat do servidor (alimenta o CCU) |
| `forwardToRobloxAnalytics` | `boolean` | `false` | — | repassa cada `Log*` ao `AnalyticsService` nativo |
| `debug` | `boolean` | `false` | — | logs detalhados no Output |
| `enabledInStudio` | `boolean` | `false` | — | envia também durante o Play no Studio |

Comportamento com valor inválido:

- Tipo errado → aviso e valor padrão.
- Fora do intervalo → aviso e o valor mais próximo permitido.
- `maxQueueSize` menor que `maxBatchSize` → usa `maxBatchSize`.
- `endpoint` que não é URL http(s) → aviso e endpoint padrão.
- `key` ausente, vazia ou de tipo errado → o `init` falha com aviso e o SDK fica desligado (o jogo segue normal).

## Tipo

```lua
export type Options = {
	key: (string | Secret)?,
	endpoint: string?,
	flushInterval: number?,
	maxBatchSize: number?,
	maxQueueSize: number?,
	heartbeatInterval: number?,
	forwardToRobloxAnalytics: boolean?,
	debug: boolean?,
	enabledInStudio: boolean?,
}
```
