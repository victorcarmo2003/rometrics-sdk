# API do módulo RoMetrics

```lua
local RoMetrics = require(game:GetService("ReplicatedStorage"):WaitForChild("RoMetrics"))
```

Servidor apenas. Funções com `.` são chamadas como função; as com `:` são métodos (mesma convenção do `AnalyticsService`). Nenhuma lança erro.

| Membro | Resumo |
|---|---|
| [`RoMetrics.init(options)`](#init) | liga o SDK; chame uma vez |
| [`RoMetrics.wrapProcessReceipt(handler)`](#wrapprocessreceipt) | conta vendas de Developer Products |
| [`RoMetrics:LogCustomEvent(...)`](#logcustomevent) | evento custom de um jogador |
| [`RoMetrics:LogEconomyEvent(...)`](#logeconomyevent) | moeda ganha/gasta |
| [`RoMetrics:LogFunnelStepEvent(...)`](#logfunnelstepevent) | passo de funil |
| [`RoMetrics:LogOnboardingFunnelStepEvent(...)`](#logonboardingfunnelstepevent) | passo do funil `Onboarding` |
| [`RoMetrics:LogProgressionEvent(...)`](#logprogressionevent) | início/falha/conclusão de nível |
| [`RoMetrics:track(...)`](#track) | evento livre, com ou sem jogador |
| [`RoMetrics:flush()`](#flush) | força o envio |
| [`RoMetrics.VERSION`](#version) | versão do SDK |

Rastreado automaticamente após o `init`: início/heartbeat/fim do servidor, entrada e saída de jogadores (com país, Premium, idade da conta e origem), Game Passes, plataforma e eventos de [tags](/guia/tags). Veja [Dados enviados](/referencia/dados-enviados).

---

## init

### `RoMetrics.init(options: Options): ()`

Liga o SDK. Chame **uma vez**, no começo de um Script de servidor. Chamadas repetidas são ignoradas com aviso; chamada no cliente é ignorada.

```lua
RoMetrics.init({
	key = HttpService:GetSecret("rometrics_key"),
	debug = false,
})
```

| Campo | Tipo | Padrão |
|---|---|---|
| `key` | `Secret \| string` | **obrigatório** |
| `endpoint` | `string?` | `"https://ingest.rometrics.app"` |
| `flushInterval` | `number?` | `10` |
| `maxBatchSize` | `number?` | `100` |
| `maxQueueSize` | `number?` | `5000` |
| `heartbeatInterval` | `number?` | `30` |
| `forwardToRobloxAnalytics` | `boolean?` | `false` |
| `debug` | `boolean?` | `false` |
| `enabledInStudio` | `boolean?` | `false` |

Intervalos e efeitos: [Opções do init](/referencia/opcoes). Sem `key` (ou vazia) o `init` falha com aviso e o SDK fica desligado; o jogo continua normal.

---

## wrapProcessReceipt

### `RoMetrics.wrapProcessReceipt(handler: (receiptInfo) -> Enum.ProductPurchaseDecision): (receiptInfo) -> Enum.ProductPurchaseDecision`

Devolve um `ProcessReceipt` que executa o seu `handler` e conta a venda quando ele retorna `PurchaseGranted`.

```lua
MarketplaceService.ProcessReceipt = RoMetrics.wrapProcessReceipt(function(receiptInfo)
	-- entregue o item
	return Enum.ProductPurchaseDecision.PurchaseGranted
end)
```

- Retorna exatamente a decisão do seu `handler`.
- Erro no `handler` → aviso no Output e `NotProcessedYet`.
- Cada `PurchaseId` é contado uma vez por servidor. Pode ser usado antes do `init`.

---

## LogCustomEvent

### `RoMetrics:LogCustomEvent(player: Player, eventName: string, value: number?, customFields: { [string]: any }?): ()`

```lua
RoMetrics:LogCustomEvent(player, "BossKilled", 1, { boss = "Dragon" })
```

---

## LogEconomyEvent

### `RoMetrics:LogEconomyEvent(player: Player, flowType: Enum.AnalyticsEconomyFlowType, currencyType: string, amount: number, endingBalance: number, transactionType: string, itemSku: string?, customFields: { [string]: any }?): ()`

```lua
RoMetrics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, "Coins", 50, 550, "Quest", nil)
```

`flowType`: `Source` (entrou) ou `Sink` (saiu), como Enum ou string. `transactionType` e `itemSku` até 64 caracteres.

---

## LogFunnelStepEvent

### `RoMetrics:LogFunnelStepEvent(player: Player, funnelName: string, funnelSessionId: string?, step: number, stepName: string?, customFields: { [string]: any }?): ()`

```lua
RoMetrics:LogFunnelStepEvent(player, "Shop", attemptId, 2, "SelectedItem")
```

`step` é inteiro a partir de `1`. `funnelSessionId` (até 64) agrupa uma tentativa; `stepName` até 64.

---

## LogOnboardingFunnelStepEvent

### `RoMetrics:LogOnboardingFunnelStepEvent(player: Player, step: number, stepName: string?, customFields: { [string]: any }?): ()`

Atalho para o funil `"Onboarding"` (enviado com `onboarding = true`).

```lua
RoMetrics:LogOnboardingFunnelStepEvent(player, 3, "Primeira compra")
```

---

## LogProgressionEvent

### `RoMetrics:LogProgressionEvent(player: Player, progressionPathName: string, status: Enum.AnalyticsProgressionType, level: number, levelName: string?, customFields: { [string]: any }?): ()`

```lua
RoMetrics:LogProgressionEvent(player, "World1", Enum.AnalyticsProgressionType.Fail, 4, "Boss")
```

`status`: `Start`, `Fail` ou `Complete` (Enum ou string). `Custom` não é suportado e é descartado.

---

## track

### `RoMetrics:track(eventName: string, opts: { player: Player?, value: number?, props: { [string]: any }? }?): ()`

Evento custom livre. Sem `player`, vira um evento do servidor.

```lua
RoMetrics:track("RoundStarted", { value = 1, props = { map = "Desert" } })
RoMetrics:track("ShopOpened", { player = player })
```

Não é repassado ao `AnalyticsService` nativo.

---

## flush

### `RoMetrics:flush(): ()`

Agenda o envio imediato do que está na fila (assíncrono). Normalmente desnecessário: o SDK envia a cada `flushInterval` e no desligamento.

---

## VERSION

### `RoMetrics.VERSION: string`

Versão do SDK, ex. `"0.3.0"`. Também enviada em todo lote.

---

## Regras comuns

- **Nomes** (evento, funil, caminho, moeda): `^[A-Za-z0-9_.:-]{1,64}$`. Fora do padrão vira `_`; acima de 64 é cortado; vazio é descartado.
- **Campos** (`customFields`, `props`): valores string/number/boolean (o resto vira texto), chave até 64, texto até 256, total ~2 KB; excedente descartado em ordem alfabética das chaves com `_truncated = true`.
- **`value` / números**: precisam ser finitos.
- **Jogador**: precisa estar no servidor e o `init` já ter rodado; senão o evento é descartado.
- Chamadas antes do `init` são ignoradas (exceto `wrapProcessReceipt`, que funciona sem rastrear).
