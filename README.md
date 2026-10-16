<p align="center">
  <img src="docs/public/logo.svg" width="64" height="64" alt="RoMetrics">
</p>

<h1 align="center">RoMetrics SDK</h1>

<p align="center">
  Analytics em tempo real para jogos Roblox: SDK Luau para o servidor e plugin do Roblox Studio.<br>
  <a href="https://victorcarmo2003.github.io/rometrics-sdk/"><strong>Documentação</strong></a> ·
  <a href="https://victorcarmo2003.github.io/rometrics-sdk/referencia/sdk">API</a> ·
  <a href="https://victorcarmo2003.github.io/rometrics-sdk/ia">Para sua IA (.md)</a> ·
  <a href="https://github.com/victorcarmo2003/rometrics-sdk/releases/latest">Downloads</a>
</p>

---

- **Tempo real**: CCU, entradas e vendas no dashboard em segundos, não em 48 horas.
- **API igual ao `AnalyticsService`**: `LogCustomEvent`, `LogEconomyEvent`, `LogFunnelStepEvent`, `LogProgressionEvent`.
- **Vendas automáticas**: Game Passes sozinhos; Developer Products com um wrapper no `ProcessReceipt`.
- **Eventos sem código**: marque Parts, prompts e Tools pelo plugin do Studio.
- **Nunca quebra o jogo**: nenhuma chamada lança erro; fila com reenvio e flush no desligamento.

## Uso rápido

```lua
-- ServerScriptService/RoMetricsSetup (Script)
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local RoMetrics = require(game:GetService("ReplicatedStorage"):WaitForChild("RoMetrics"))

RoMetrics.init({ key = HttpService:GetSecret("rometrics_key") })

MarketplaceService.ProcessReceipt = RoMetrics.wrapProcessReceipt(function(receiptInfo)
	-- entregue o item
	return Enum.ProductPurchaseDecision.PurchaseGranted
end)

RoMetrics:LogCustomEvent(player, "BossKilled", 1, { boss = "Dragon" })
```

Passo a passo completo: [Começando](https://victorcarmo2003.github.io/rometrics-sdk/guia/comecando).

## Downloads

| Arquivo | O que é |
|---|---|
| [`RoMetrics.rbxm`](https://github.com/victorcarmo2003/rometrics-sdk/releases/latest/download/RoMetrics.rbxm) | SDK (ModuleScript). Insira em `ReplicatedStorage` |
| [`RoMetricsPlugin.rbxm`](https://github.com/victorcarmo2003/rometrics-sdk/releases/latest/download/RoMetricsPlugin.rbxm) | Plugin do Studio. Copie para a pasta de Plugins |

Também via Wally: `RoMetrics = "victorcarmo2003/rometrics@0.1.0"`.

## Usando com IA

Envie [`rometrics-sdk.ai.md`](https://victorcarmo2003.github.io/rometrics-sdk/rometrics-sdk.ai.md) para o ChatGPT, Claude, Gemini ou Cursor: um único arquivo com toda a API, regras e erros comuns. Índice para ferramentas: [`llms.txt`](https://victorcarmo2003.github.io/rometrics-sdk/llms.txt).

## Estrutura

```
sdk/roblox/   SDK Luau (src, tests, examples, dist/RoMetrics.rbxm)
plugin/       Plugin do Studio (src, tests, dist/RoMetricsPlugin.rbxm)
docs/         Site de documentação (VitePress) + arquivo para IA
```

## Desenvolvimento

Ferramentas em [`rokit.toml`](rokit.toml) (`rokit install`):

```bash
cd sdk/roblox && lune run tests/run.luau     # testes do SDK
lune run plugin/tools/run-tests.luau         # testes do plugin (na raiz)
selene sdk/roblox/src plugin/src             # lint
rojo build sdk/roblox/default.project.json -o RoMetrics.rbxm
```

Docs: `npm install` e `npm run docs:dev`.

## Licença

[MIT](LICENSE)
