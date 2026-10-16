# Instalação do plugin

1. Feche o Roblox Studio.
2. Baixe [`RoMetricsPlugin.rbxm`](https://github.com/victorcarmo2003/rometrics-sdk/releases/latest/download/RoMetricsPlugin.rbxm).
3. Copie o arquivo para a pasta de plugins:
   - **Windows**: `%LOCALAPPDATA%\Roblox\Plugins` (cole na barra do Explorador de Arquivos).
   - **macOS**: `~/Documents/Roblox/Plugins`.
   - Atalho: no Studio, **Plugins → Plugins Folder** abre a pasta certa.
4. Abra o Studio. Na aba **Plugins** aparece o botão **RoMetrics**; clique para abrir o painel.

## A partir do código

```bash
rojo build plugin/default.project.json -o RoMetricsPlugin.rbxm
```

## Permissão de HTTP

O botão **Instalar do GitHub** (aba Início) baixa o SDK de `api.github.com` e `raw.githubusercontent.com`: aceite a permissão de HTTP que o Studio pede na primeira vez. O botão **Testar conexão** (abas Início e Config) faz um `GET {endpoint}/health`. Na primeira vez o Studio pede permissão para o domínio (*Plugin Management → permissões*). O plugin **nunca** lê nem guarda a sua chave: Secrets só existem no servidor do jogo.
