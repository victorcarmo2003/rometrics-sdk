# Testando no Studio

Por padrão o SDK **não envia nada** durante o Play no Studio (`enabledInStudio = false`), para não sujar seus dados com testes. Para testar de verdade:

1. **Allow HTTP Requests** ligado (*File → Experience Settings → Security*).
2. O jogo **publicado** (Universe ID diferente de `0`).
3. `enabledInStudio = true` e uma chave que funcione no Studio.

## Script de setup para Studio e produção

```lua
--!strict
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoMetrics = require(ReplicatedStorage:WaitForChild("RoMetrics")) :: any

-- SÓ chave de teste aqui. Em produção a chave vem do Secrets Store.
local STUDIO_KEY = "rmk_live_YOUR_TEST_KEY"
local STUDIO_ENDPOINT: string? = nil -- ex.: "http://localhost:4100" para um ingest local

local okSecret, secret = pcall(function()
	return HttpService:GetSecret("rometrics_key")
end)
local isStudio = RunService:IsStudio()

RoMetrics.init({
	key = if okSecret then secret elseif isStudio then STUDIO_KEY else nil,
	endpoint = if isStudio then STUDIO_ENDPOINT else nil, -- nil = endpoint padrão
	enabledInStudio = true,
	debug = isStudio, -- detalhes no Output enquanto testa
})
```

Aperte **Play**. O Output mostra `[RoMetrics] initialized v0.3.1` e, com `debug`, `sent N events (202)` a cada ~10 s. Abra o dashboard em **Ao vivo** e **Eventos**.

Quando você para o Play, o SDK envia `player_leave` e `server_stop` antes de fechar (até 25 s).

## Test → Start (vários jogadores)

Os jogadores de teste do *Test → Start* têm UserId negativo (Player1 = `-1`). O SDK converte para ids de teste `10000000000000 + |UserId|` (`10000000000001`, `10000000000002`…) para o servidor aceitar e para não colidirem com jogadores reais. No Play normal o Studio usa o seu UserId real.

## Ingest local

Se você roda o backend do RoMetrics na sua máquina, use `STUDIO_ENDPOINT = "http://localhost:4100"`. O Studio permite `localhost`. Se a sua rede bloquear, crie um túnel HTTPS (por exemplo `cloudflared tunnel --url http://localhost:4100`) e use a URL do túnel.
