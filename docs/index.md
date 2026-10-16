---
layout: home

hero:
  name: RoMetrics SDK
  text: Analytics em tempo real para jogos Roblox
  tagline: Jogadores, vendas e eventos chegando no seu dashboard em segundos, não em 48 horas. Um módulo Luau no servidor e um plugin do Studio para marcar eventos sem código.
  image:
    src: /logo.svg
    alt: RoMetrics
  actions:
    - theme: brand
      text: Começar
      link: /guia/comecando
    - theme: alt
      text: Referência da API
      link: /referencia/sdk
    - theme: alt
      text: Enviar para minha IA
      link: /ia

features:
  - icon: ⚡
    title: Tempo real
    details: CCU, entradas, vendas de Game Pass e Developer Product aparecem no dashboard em segundos, com notificação de cada venda.
  - icon: 🧩
    title: API igual ao AnalyticsService
    details: LogCustomEvent, LogEconomyEvent, LogFunnelStepEvent e LogProgressionEvent com a mesma assinatura do serviço nativo. Opcionalmente repassa tudo para ele.
  - icon: 🏷️
    title: Eventos sem código
    details: Selecione uma Part, ProximityPrompt, ClickDetector ou Tool no Studio, aplique uma tag pelo plugin e o evento é enviado sozinho.
  - icon: 🛡️
    title: Nunca quebra o jogo
    details: Nenhuma chamada lança erro para o seu código. Fila com reenvio, backoff, limite de requisições e flush no BindToClose.
  - icon: 🔗
    title: Atribuição de campanhas
    details: Links de rastreio com launchData mostram quantos jogadores e quanto Robux cada canal trouxe.
  - icon: 🤖
    title: Feito para usar com IA
    details: Um único arquivo .md com toda a API e as regras, pronto para colar no ChatGPT, Claude ou Cursor.
---

## Em 30 segundos

```lua
-- ServerScriptService/RoMetricsSetup (Script)
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local RoMetrics = require(game:GetService("ReplicatedStorage").RoMetrics)

RoMetrics.init({ key = HttpService:GetSecret("rometrics_key") })

MarketplaceService.ProcessReceipt = RoMetrics.wrapProcessReceipt(function(receiptInfo)
	-- entregue o item...
	return Enum.ProductPurchaseDecision.PurchaseGranted
end)

RoMetrics:LogCustomEvent(player, "BossKilled", 1, { boss = "Dragon" })
```

Baixe o [SDK (.rbxm)](https://github.com/victorcarmo2003/rometrics-sdk/releases/latest/download/RoMetrics.rbxm) e o [plugin (.rbxm)](https://github.com/victorcarmo2003/rometrics-sdk/releases/latest/download/RoMetricsPlugin.rbxm), ou siga o [passo a passo](/guia/comecando).
