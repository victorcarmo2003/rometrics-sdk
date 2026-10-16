# Configuração

Tudo é passado para `RoMetrics.init` uma única vez, no começo do servidor. Só a chave é obrigatória.

```lua
RoMetrics.init({
	key = HttpService:GetSecret("rometrics_key"), -- obrigatória
	endpoint = "https://ingest.rometrics.app",   -- host do ingest
	flushInterval = 10,          -- segundos entre envios
	maxBatchSize = 100,          -- eventos por envio
	maxQueueSize = 5000,         -- buffer em memória
	heartbeatInterval = 30,      -- segundos entre heartbeats do servidor
	forwardToRobloxAnalytics = false,
	debug = false,
	enabledInStudio = false,
})
```

Valores inválidos não quebram nada: o SDK avisa no Output e usa o padrão (ou o valor mais próximo do intervalo permitido). Tabela completa com limites: [Opções do init](/referencia/opcoes).

## Endpoint

Use o endereço do ingest informado no seu dashboard. Se você hospeda o RoMetrics, aponte para o seu servidor (`https://ingest.seudominio.com`). Barras no fim são removidas.

## Debug

`debug = true` mostra no Output cada envio (`sent N events (202)`), descartes e motivos. Deixe ligado enquanto testa e desligue em produção.

## Repassar para o AnalyticsService

Com `forwardToRobloxAnalytics = true`, cada chamada `Log*` também vai para o `AnalyticsService` nativo com os argumentos originais. Útil para manter os gráficos do Creator Hub enquanto migra. Detalhes em [Eventos](/guia/eventos#repassando-para-o-analyticsservice).

## Studio

Por padrão nada é enviado durante o Play no Studio. Veja [Testando no Studio](/guia/testando-no-studio).
