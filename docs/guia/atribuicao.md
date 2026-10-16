# Atribuição (deep links)

Para saber quantos jogadores e quanto Robux cada canal trouxe (YouTube, TikTok, Discord, influenciador), use **links de rastreio**. Crie no dashboard em **Atribuição → Links de rastreio**; cada link tem um código curto.

O link gerado abre o jogo com `launchData`:

```
https://www.roblox.com/games/start?placeId=<PLACE_ID>&launchData=rm%3D<codigo>
```

Nada precisa ser feito no jogo: o SDK lê `player:GetJoinData().LaunchData` na entrada e envia o código junto com o `player_join`. A partir daí, toda compra desse jogador conta para o link.

## Formatos aceitos

O SDK encontra o código em qualquer um destes `launchData`:

- `rm=yt01`
- `a=1&rm=yt01` (junto com parâmetros seus)
- `{"rm":"yt01"}` (JSON)

## Teleports entre places

Se o jogador entra pelo place A e é teleportado para o B, repasse o código em `TeleportData.rm` para manter a origem:

```lua
local TeleportService = game:GetService("TeleportService")

-- Código de rastreio com que o jogador entrou neste place (letras, números, _ e -, até 64).
local function launchCode(player: Player): string?
	local launch = player:GetJoinData().LaunchData
	if typeof(launch) == "string" then
		return string.match(launch, "rm=([%w_%-]+)")
	end
	return nil
end

local options = Instance.new("TeleportOptions")
options:SetTeleportData({ rm = launchCode(player) })
TeleportService:TeleportAsync(PLACE_B_ID, { player }, options)
```

No place B, quando não há `LaunchData`, o SDK usa `TeleportData.rm`.

## Campanhas de anúncio da Roblox

Anúncios nativos não passam `launchData`. Para eles, o dashboard estima a atribuição pela janela em que a campanha esteve ativa, comparando com o tráfego normal.
