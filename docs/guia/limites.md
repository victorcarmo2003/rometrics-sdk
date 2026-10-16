# Limites e confiabilidade

O SDK foi feito para nunca atrapalhar o jogo e respeitar os limites da Roblox sozinho.

## O que ele garante

- **Nunca lança erro** para o seu código. Toda função pública roda em `pcall`; problemas viram aviso no Output.
- **Não bloqueia o gameplay**: envios rodam em `task.spawn`, um por vez.
- **HttpService**: a Roblox permite 500 requisições/min por servidor. O SDK usa no máximo ~30/min (um envio a cada 2 s no pior caso), sobrando espaço para o seu jogo.
- **Lotes**: até `maxBatchSize` eventos (padrão 100), corpo abaixo de 1 MB (lotes grandes são divididos). Compressão gzip para corpos a partir de 1 KB.
- **Fila em memória**: até `maxQueueSize` eventos (padrão 5000). Se o servidor ficar muito tempo sem conseguir enviar, os mais antigos são descartados e contados no heartbeat (`dropped`).
- **Reenvio**: erros de rede, `429` e `5xx` voltam para a frente da fila com backoff exponencial de 2 s até 60 s (com jitter), respeitando `Retry-After`.
- **Circuit breaker**: 5 falhas seguidas pausam os envios por 60 s.
- **Chave inválida** (`401`/`403`): o SDK para de enviar até o servidor reiniciar, para não gastar requisições.
- **Desligamento**: em `BindToClose` envia tudo que restou, em lotes de até 500, por até 25 s (a Roblox dá 30 s).
- **Compras**: cada `PurchaseId` conta uma vez; `GetProductInfo` tem cache de 10 min.

## Respostas do servidor

| Status | O que o SDK faz |
|---|---|
| `202` | ok |
| `400` / `413` | descarta o lote (formato inválido) e avisa |
| `401` / `403` | desliga o envio até reiniciar (chave errada, revogada ou de outro jogo) |
| `429` | espera e reenvia |
| `5xx` / rede | reenvia com backoff |

## Volume

Um servidor cheio manda tipicamente um lote a cada 10 s. O custo no jogo é desprezível: montar uma tabela por evento e um `JSONEncode` por lote.
