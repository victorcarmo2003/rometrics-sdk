# Dados enviados

Transparência sobre o que sai do seu servidor. O SDK só envia dados do próprio jogo, sempre do **servidor** para o ingest configurado, por HTTPS (`POST {endpoint}/v1/batch`, header `x-rometrics-key`).

Nenhum dado pessoal além do UserId do Roblox é coletado: sem nome, sem chat, sem IP do jogador.

## Envelope de cada lote

```json
{
  "sdk": { "name": "rometrics-luau", "version": "0.1.0" },
  "server": { "universeId": 123, "placeId": 456, "placeVersion": 78, "jobId": "…", "private": false, "startedAt": 1760000000000 },
  "sentAt": 1760000012345,
  "events": [ … ]
}
```

Todo evento tem `id` (UUID) e `ts` (epoch em ms). Eventos de jogador têm também `userId` e `sessionId`.

## Eventos automáticos

| Tipo | Quando | Dados |
|---|---|---|
| `server_start` | `init` | — |
| `heartbeat` | a cada `heartbeatInterval` | `players`, `maxPlayers`, `fps` do servidor, `uptimeS`, `dropped` |
| `server_stop` | desligamento | `uptimeS` |
| `player_join` | jogador entra | `country` (via `LocalizationService`), `premium`, `accountAgeDays`, `joinSource` { `sourcePlaceId`, `referredBy`, `launchCode`, `teleported` } |
| `player_leave` | jogador sai | `durationS` |
| `player_platform` | LocalScript reporta | `platform`, `screenW`, `screenH` |
| `purchase` | venda | `kind` (`gamepass` \| `devproduct`), `productId`, `name`, `priceRobux`, `receiptId` |

## Eventos das suas chamadas

| Tipo | Origem | Dados |
|---|---|---|
| `custom` | `LogCustomEvent`, `track`, tags | `name`, `value`, `data` (seus campos) |
| `economy` | `LogEconomyEvent` | `flow`, `currency`, `amount`, `endingBalance`, `transactionType`, `itemSku`, `customFields` |
| `funnel` | `LogFunnelStepEvent`, `LogOnboardingFunnelStepEvent` | `name`, `funnelSessionId`, `step`, `stepName`, `onboarding`, `customFields` |
| `progression` | `LogProgressionEvent` | `name`, `status`, `level`, `levelName`, `customFields` |

## Limites do servidor

Até 500 eventos e 1 MB por lote; campos de cada evento até 2 KB; nomes `^[A-Za-z0-9_.:-]{1,64}$`. Eventos com horário muito fora (mais de 24 h no passado ou 5 min no futuro) recebem o horário do envio.
