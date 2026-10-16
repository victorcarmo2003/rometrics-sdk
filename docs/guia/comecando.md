# Começando

Em uns 15 minutos você instala o plugin e o SDK, liga a chave, aperta Play e vê os eventos chegando no dashboard.

## O que você precisa

- Um jogo **publicado** no Roblox (lugar não publicado tem Universe ID `0` e o servidor recusa).
- O jogo cadastrado no dashboard RoMetrics e uma **chave de ingestão** (`rmk_live_...`) gerada para ele.
- **Allow HTTP Requests** ligado: *File → Experience Settings → Security*.

## 1. Instale o plugin (opcional, recomendado)

Baixe [`RoMetricsPlugin.rbxm`](https://github.com/victorcarmo2003/rometrics-sdk/releases/latest/download/RoMetricsPlugin.rbxm) e copie para a pasta de plugins (no Studio: **Plugins → Plugins Folder**). Reabra o Studio: aparece o botão **RoMetrics** na aba Plugins. [Detalhes](/plugin/instalacao).

## 2. Insira o SDK

Baixe [`RoMetrics.rbxm`](https://github.com/victorcarmo2003/rometrics-sdk/releases/latest/download/RoMetrics.rbxm). No Explorer: **ReplicatedStorage → botão direito → Insert from File…**. Deve aparecer o ModuleScript `ReplicatedStorage.RoMetrics`. [Outras formas de instalar](/guia/instalacao).

## 3. Guarde a chave no Secrets Store

Creator Hub → sua experiência → **Secrets** → **Create Secret**: nome `rometrics_key`, valor = sua chave, domínio = host do ingest. [Detalhes e como testar no Studio](/guia/chave-e-secrets).

## 4. Inicie o SDK no servidor

Crie um **Script** em `ServerScriptService` chamado `RoMetricsSetup`:

```lua
--!strict
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoMetrics = require(ReplicatedStorage:WaitForChild("RoMetrics")) :: any

RoMetrics.init({
	key = HttpService:GetSecret("rometrics_key"),
})

-- Developer products: embrulhe o seu ProcessReceipt para contar as vendas.
MarketplaceService.ProcessReceipt = RoMetrics.wrapProcessReceipt(function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- entregue o item aqui (DataStore etc.)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end)

Players.PlayerAdded:Connect(function(player)
	RoMetrics:LogOnboardingFunnelStepEvent(player, 1, "Entrou")
end)
```

Game passes, entradas/saídas de jogadores, servidores e plataforma são rastreados sozinhos depois do `init`.

## 5. Publique e jogue

Publique o jogo e entre num servidor ao vivo. Em segundos o dashboard mostra o jogador online (**Ao vivo**) e os eventos (**Eventos**).

::: tip Quer ver chegando já no Studio?
O SDK não envia nada durante o Play no Studio por padrão. Veja [Testando no Studio](/guia/testando-no-studio).
:::

## Próximos passos

- [Eventos](/guia/eventos): custom, economia, funis e progressão.
- [Eventos sem código](/guia/tags): marque Parts e prompts pelo plugin.
- [Referência completa](/referencia/sdk).
- Usa IA para programar? Envie [o arquivo de referência para IA](/ia).
