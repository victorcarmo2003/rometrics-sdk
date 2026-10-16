# Problemas comuns

Ligue `debug = true` no `init` para ver detalhes no Output.

| Sintoma no Output | Causa | Solução |
|---|---|---|
| `HTTP requests are disabled` | Allow HTTP Requests desligado | *File → Experience Settings → Security* |
| `option 'key' is required` / `init failed` | `GetSecret` falhou (comum no Studio) e não havia chave | [Chave e Secrets](/guia/chave-e-secrets) |
| `Can't find secret with given key` | o Secret não existe nesse ambiente | Studio: Local Secret ou chave de teste; ao vivo: crie no Creator Hub |
| `disabled in Studio` | faltou `enabledInStudio = true` | [Testando no Studio](/guia/testando-no-studio) |
| `server refused the key (401)` | chave errada, revogada ou com espaço | gere outra e atualize o Secret |
| `server refused the key (403): this key belongs to another game` | chave de outro Universe ID | gere a chave para este jogo |
| `... Universe ID 0 ... publish the place first` | lugar não publicado | *File → Publish to Roblox* |
| `server returned 429; will retry` | limite de envios do servidor | normal, o SDK espera e reenvia |
| `send failed: ConnectFail to https://ingest.rometrics.app (default endpoint not reachable: pass 'endpoint' ...)` | faltou `endpoint` no `init` (o padrão não é o seu servidor) | passe `endpoint = "https://seu-ingest"` no `RoMetrics.init` |
| `send failed: ConnectFail` / `DnsResolve` / `TimedOut to <endpoint> (check the 'endpoint' option)` | endpoint errado ou fora do ar | confira `endpoint` e o `/health` do ingest |
| `send failed: HTTP 503 from <endpoint>` | ingest com problema temporário | o SDK reenvia sozinho; se persistir, veja o servidor |
| `5 consecutive send failures (<motivo>); pausing for 60s` | envio falhando em sequência | corrija conforme o motivo entre parênteses (linhas acima) |
| Nada no Output | script não roda no servidor ou o SDK está fora do lugar | script em `ServerScriptService`; SDK em `ReplicatedStorage.RoMetrics` |
| Evento de tag não aparece | `Touched` só conta personagem de jogador; cooldown | toque com o avatar; veja a aba Validação do plugin |
| Evento com jogador descartado (`no session`) | jogador saiu ou `init` ainda não rodou | chame `init` no começo do servidor |
| Plataforma sempre `unknown` | LocalScript não chegou ao cliente | veja [Plataforma](/guia/plataforma#observacoes) |

Ainda travado? [Abra uma issue](https://github.com/victorcarmo2003/rometrics-sdk/issues) com o trecho do Output (sem a chave).
