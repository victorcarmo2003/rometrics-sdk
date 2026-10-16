# Instalação

O SDK é um único ModuleScript `RoMetrics` com submódulos. Ele **roda só no servidor**; o próprio SDK instala o pedaço de cliente quando precisa.

## Arquivo .rbxm (mais simples)

1. Baixe [`RoMetrics.rbxm`](https://github.com/victorcarmo2003/rometrics-sdk/releases/latest/download/RoMetrics.rbxm) da [última release](https://github.com/victorcarmo2003/rometrics-sdk/releases/latest).
2. No Studio, Explorer → **ReplicatedStorage** → botão direito → **Insert from File…** → escolha o arquivo.
3. Não renomeie nem mova os filhos do módulo.

```lua
local RoMetrics = require(game:GetService("ReplicatedStorage"):WaitForChild("RoMetrics"))
```

::: info Por que em ReplicatedStorage?
Assim o SDK consegue copiar o LocalScript de [plataforma](/guia/plataforma) para `StarterPlayerScripts`. Se preferir `ServerScriptService`, funciona igual, mas copie `RoMetrics/Client/RoMetricsClient` para `StarterPlayerScripts` à mão.
:::

## Wally

```toml
# wally.toml
[dependencies]
RoMetrics = "victorcarmo2003/rometrics@0.3.0"
```

```bash
wally install
```

O pacote fica em `ReplicatedStorage.Packages.RoMetrics`.

## Rojo (a partir do código)

Clone o repositório e aponte seu projeto para `sdk/roblox/src`, ou gere o modelo:

```bash
cd sdk/roblox
rojo build default.project.json -o RoMetrics.rbxm
```

## Atualizando

Substitua o ModuleScript inteiro pela versão nova. A configuração fica no seu script de setup, não dentro do módulo, então nada se perde. Veja o [changelog](/changelog).
