# Atributos de tag (RM_*)

Instâncias com a tag **`RoMetrics`** (CollectionService) e os atributos abaixo enviam eventos sozinhas. Guia: [Eventos sem código](/guia/tags).

| Atributo | Tipo | Obrigatório | Significado |
|---|---|---|---|
| `RM_Event` | `string` | sim | nome do evento custom enviado (regras de nome valem) |
| `RM_Trigger` | `string` | não | `Touched`, `ProximityPrompt`, `ClickDetector` ou `Activated`. Ausente = inferido pela classe |
| `RM_Value` | `number` | não | `value` do evento |
| `RM_Cooldown` | `number` (s) | não | intervalo mínimo por jogador **nesta instância**. `Touched` usa no mínimo 1 s |
| `RM_Once` | `boolean` | não | dispara uma vez por sessão do jogador (por instância) |
| `RM_Prop_<chave>` | `string \| number \| boolean` | não | props extras: `RM_Prop_zone = "Lobby"` → `{ zone = "Lobby" }` |

Props adicionadas automaticamente (a menos que você defina em `RM_Prop_*`): `trigger` e `instance` (nome da instância).

## Inferência do gatilho

| Classe | Gatilho |
|---|---|
| `ProximityPrompt` | `ProximityPrompt` |
| `ClickDetector` | `ClickDetector` |
| `Tool` | `Activated` |
| `BasePart`, `Model`, `Folder` | `Touched` |

Para `ProximityPrompt`/`ClickDetector` numa Part ou Model, o SDK usa o primeiro descendente da classe (e espera ele aparecer, se ainda não existe).

## Exemplo

```lua
local CollectionService = game:GetService("CollectionService")

local chest = workspace.Map.Chest
chest:SetAttribute("RM_Event", "ChestOpened")
chest:SetAttribute("RM_Trigger", "ProximityPrompt")
chest:SetAttribute("RM_Once", true)
chest:SetAttribute("RM_Prop_rarity", "epic")
CollectionService:AddTag(chest, "RoMetrics")
```

Mudanças em tempo de jogo (tag adicionada/removida, atributo alterado) religam o gatilho. Atributo inválido → aviso com `debug = true` e a instância é ignorada.
