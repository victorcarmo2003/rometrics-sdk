# Compras

## Developer Products

Embrulhe o seu `ProcessReceipt` com `RoMetrics.wrapProcessReceipt`. Note o `.` (função, não método):

```lua
MarketplaceService.ProcessReceipt = RoMetrics.wrapProcessReceipt(function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- entregue o item e salve antes de confirmar
	return Enum.ProductPurchaseDecision.PurchaseGranted
end)
```

O que o wrapper garante:

- Seu handler roda em `pcall` e a decisão que **ele** retorna é devolvida para a Roblox, sem alteração.
- Se o seu handler der erro, o wrapper loga e retorna `NotProcessedYet`: a Roblox tenta de novo depois e o jogador não perde o item.
- A venda só é contada com `PurchaseGranted`: preço = `CurrencySpent`, id do recibo = `PurchaseId`, nome via `GetProductInfo` (cache de 10 min).
- Cada `PurchaseId` é contado uma vez por servidor, mesmo que a Roblox repita o recibo.
- O rastreio roda em `task.spawn`, sem atrasar a resposta.
- Funciona mesmo se `init` não rodou: o handler executa normalmente, só não há rastreio.

::: warning Só um ProcessReceipt
A Roblox aceita um único `ProcessReceipt` por jogo. Se você usa um roteador de produtos, embrulhe o roteador inteiro.
:::

## Game Passes

Automático. O SDK escuta `MarketplaceService.PromptGamePassPurchaseFinished` e conta quando `wasPurchased = true`, com nome e preço vindos de `GetProductInfo(id, Enum.InfoType.GamePass)` (cache e 3 tentativas).

Compras de Game Pass feitas fora do jogo (pelo site) não passam pelo servidor e não aparecem.

## Assinaturas

Ainda não rastreadas.

## No dashboard

Cada venda aparece em segundos em **Receita** e no feed **Ao vivo**, com país, plataforma e a campanha que trouxe o jogador, e pode disparar notificação (Discord, push no celular ou no navegador).
