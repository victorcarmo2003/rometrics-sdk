# Plataforma do jogador

O servidor não sabe se o jogador está no celular, PC, console ou VR. Por isso o SDK tem um pequeno pedaço de cliente.

Quando o `init` roda, o SDK:

1. Cria o RemoteEvent `ReplicatedStorage.RoMetricsClient`.
2. Copia o LocalScript `RoMetricsClient` para `StarterPlayerScripts` (se ainda não estiver lá).

O LocalScript envia **um** relatório por sessão: `desktop`, `mobile`, `tablet`, `console`, `vr` ou `unknown`, mais o tamanho da tela. O dashboard usa isso em **Jogadores → Plataformas** e no detalhe de cada venda.

## Como detecta

| Sinal | Plataforma |
|---|---|
| `VRService.VREnabled` | `vr` |
| `GuiService:IsTenFootInterface()`, ou gamepad sem teclado | `console` |
| Toque sem teclado, lado menor da tela < 600 | `mobile` |
| Toque sem teclado, lado menor da tela ≥ 600 | `tablet` |
| Teclado | `desktop` |

## Segurança

O servidor valida o payload (plataforma conhecida, tamanhos plausíveis) e ignora qualquer relatório depois do primeiro válido. Um cliente malicioso só consegue mentir a própria plataforma.

## Observações

- Jogadores que entraram antes do `init` não recebem o script. Chame `init` logo no começo do servidor.
- Se o módulo estiver num lugar sem acesso a `StarterPlayerScripts`, copie `RoMetrics/Client/RoMetricsClient` para lá manualmente.
