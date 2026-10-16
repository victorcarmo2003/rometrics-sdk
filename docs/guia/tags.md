# Eventos sem código (tags)

Marque instâncias no Studio e o SDK envia o evento sozinho quando um jogador interage. Ideal para portais, baús, botões do mapa, NPCs e ferramentas.

## Pelo plugin

1. Aba **Eventos** → **Novo**: nome (ex.: `PortalTouched`), tipo `custom` → **Salvar**.
2. Selecione a instância no Explorer.
3. Aba **Rastrear** → escolha o evento, o gatilho, cooldown ou "uma vez" → **Aplicar**.

O plugin aplica a tag `RoMetrics` e os atributos `RM_*`. **Ctrl+Z** desfaz.

## Na mão (ou por script)

```lua
local CollectionService = game:GetService("CollectionService")

local portal = workspace.Lobby.Portal
portal:SetAttribute("RM_Event", "PortalTouched")
portal:SetAttribute("RM_Trigger", "Touched")
portal:SetAttribute("RM_Cooldown", 5)
portal:SetAttribute("RM_Prop_zone", "Lobby")
CollectionService:AddTag(portal, "RoMetrics")
```

## Gatilhos

| `RM_Trigger` | Instância | Quem é o jogador |
|---|---|---|
| `Touched` | `BasePart`, ou `Model`/`Folder` (liga todas as `BasePart` descendentes) | dono do personagem que tocou; NPC e peça solta são ignorados |
| `ProximityPrompt` | o prompt ou o primeiro descendente `ProximityPrompt` | quem acionou (`Triggered`) |
| `ClickDetector` | o detector ou o primeiro descendente `ClickDetector` | quem clicou (`MouseClick`) |
| `Activated` | `Tool` | dono do personagem que segura a ferramenta |

Sem `RM_Trigger`, o gatilho é inferido pela classe: ProximityPrompt, ClickDetector, Tool → `Activated`, BasePart/Model → `Touched`.

`Touched` tem cooldown mínimo de 1 s por jogador e instância, mesmo sem `RM_Cooldown`, porque o Roblox dispara Touched dezenas de vezes por contato.

## O que é enviado

Um evento custom com o nome de `RM_Event`, `value = RM_Value` e as props `RM_Prop_*`, mais `trigger` e `instance` (nome da instância) adicionados automaticamente.

Tudo é dinâmico: instâncias marcadas, desmarcadas ou com atributos alterados durante o jogo são religadas. Atributo inválido gera aviso (com `debug = true`) e a instância é ignorada.

Lista completa de atributos: [Atributos de tag](/referencia/atributos).

::: info Botões de interface (GuiButton)
Ainda não suportados por tag, porque rodam no cliente. Use seu próprio RemoteEvent e chame `LogCustomEvent` no servidor.
:::
