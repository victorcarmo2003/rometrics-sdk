# Eventos

A API de eventos tem **a mesma assinatura do [AnalyticsService](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService)** nativo. Se você já usa o nativo, basta trocar `AnalyticsService` por `RoMetrics`.

Todas as chamadas usam `:` (método) e nunca lançam erro: entrada inválida é descartada com aviso no Output.

## Evento custom

```lua
RoMetrics:LogCustomEvent(player, "BossKilled", 1, { boss = "Dragon", difficulty = 3 })
```

| Parâmetro | Tipo | |
|---|---|---|
| `player` | `Player` | jogador no servidor |
| `eventName` | `string` | nome do evento |
| `value` | `number?` | valor numérico livre (somado no dashboard) |
| `customFields` | `{ [string]: any }?` | campos extras |

## Evento sem jogador: `track`

Para eventos do servidor (evento de mapa, boss global, início de rodada):

```lua
RoMetrics:track("RoundStarted", { value = 1, props = { map = "Desert" } })
-- ou atribuindo a um jogador:
RoMetrics:track("ShopOpened", { player = player })
```

## Economia

```lua
RoMetrics:LogEconomyEvent(
	player,
	Enum.AnalyticsEconomyFlowType.Sink, -- Source (ganhou) ou Sink (gastou)
	"Coins",       -- moeda
	100,           -- quantidade
	450,           -- saldo depois
	"Shop",        -- tipo da transação
	"Sword",       -- item (opcional)
	{ tier = "rare" } -- campos (opcional)
)
```

`flowType` aceita o Enum ou as strings `"Source"`/`"Sink"`.

## Funis

```lua
local funnelSessionId = HttpService:GenerateGUID(false) -- opcional: agrupa uma tentativa
RoMetrics:LogFunnelStepEvent(player, "Tutorial", funnelSessionId, 1, "Spawned")
RoMetrics:LogFunnelStepEvent(player, "Tutorial", funnelSessionId, 2, "OpenedShop")
```

`step` começa em `1`. O dashboard mostra a conversão de cada passo e onde os jogadores mais desistem.

Onboarding tem um atalho, que vira o funil `"Onboarding"`:

```lua
RoMetrics:LogOnboardingFunnelStepEvent(player, 1, "Entrou")
RoMetrics:LogOnboardingFunnelStepEvent(player, 2, "Completou tutorial")
```

## Progressão

```lua
RoMetrics:LogProgressionEvent(player, "World1", Enum.AnalyticsProgressionType.Complete, 5, "Lava Cave")
```

`status` aceita `Start`, `Fail` e `Complete` (Enum ou string). `Custom` é descartado.

## Regras de validação

- **Nomes** (evento, funil, caminho de progressão, moeda): `^[A-Za-z0-9_.:-]{1,64}$`. Caracteres fora disso viram `_`; acima de 64 é cortado; nome vazio é descartado.
- **customFields / props**: só valores simples (texto, número, booleano; o resto vira `tostring`). Chaves até 64 caracteres, textos até 256, total ~2 KB. O excedente é descartado em ordem alfabética das chaves e `_truncated = true` é adicionado.
- `value` precisa ser um número finito.
- Eventos com jogador exigem que ele esteja no servidor e que o `init` já tenha rodado.

## Repassando para o AnalyticsService

Com `forwardToRobloxAnalytics = true` no `init`, cada `Log*` também chama o nativo com os argumentos originais (em `pcall`; falhas do nativo não afetam o RoMetrics).

- O nativo só aceita as chaves `Enum.AnalyticsCustomFieldKeys.CustomField01..03` em `customFields`. Use-as se quiser os campos também no Creator Hub.
- `track` não é repassado (o nativo exige jogador).

## Forçar envio

Os eventos saem em lotes a cada `flushInterval` segundos ou quando o lote enche. Para mandar agora:

```lua
RoMetrics:flush()
```

No desligamento do servidor o SDK faz o flush final sozinho.
