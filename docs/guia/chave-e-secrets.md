# Chave e Secrets

Cada jogo (Universe ID) tem sua **chave de ingestão** `rmk_live_...`, criada no dashboard em **Configurações → Chaves de ingestão**. Ela só aparece uma vez: copie na hora.

A chave só vale para o Universe ID em que foi criada. Usada em outro jogo, o servidor responde `403`.

## Em produção: Secrets Store

Nunca deixe a chave no código. Use o [Secrets Store](https://create.roblox.com/docs/cloud-services/secrets) da Roblox:

1. Creator Hub → sua experiência → **Secrets** → **Create Secret**.
2. **Name**: `rometrics_key`. **Secret**: a chave. **Domain**: o host do ingest (ex.: `ingest.rometrics.app`, ou o host do seu servidor).
3. No servidor:

```lua
RoMetrics.init({ key = HttpService:GetSecret("rometrics_key") })
```

O SDK coloca o `Secret` direto no header `x-rometrics-key`. Secrets só podem ir em header ou URL, nunca no corpo da requisição, e é exatamente assim que o SDK usa.

## No Studio

Durante o **Play** local, `GetSecret` não enxerga o Secrets Store do jogo (erro `Can't find secret with given key`). Duas saídas:

- **Local Secret**: *File → Experience Settings → Security → Local Secrets*, crie `rometrics_key` com a chave e o domínio.
- **Chave de teste em texto, só no Studio**: veja o script em [Testando no Studio](/guia/testando-no-studio).

::: warning
Use texto apenas com uma chave de **teste** e apenas quando `RunService:IsStudio()`. Uma chave escrita no código acaba no arquivo do jogo e pode vazar.
:::

**Team Test** usa o Secrets Store do jogo, igual aos servidores ao vivo.

## Rotacionando uma chave

Gere uma nova no dashboard, atualize o Secret e revogue a antiga. A revogação vale em até alguns minutos; servidores que ainda usam a chave antiga recebem `401` e o SDK para de enviar até reiniciar.
