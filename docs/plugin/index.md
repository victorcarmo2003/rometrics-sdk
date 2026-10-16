# Plugin do Roblox Studio

O plugin RoMetrics gerencia o SDK dentro do Studio: instalação do SDK em 1 clique, registro de eventos, marcação de instâncias por tag (eventos sem código), snippets prontos, editor de funis e validação antes de publicar.

- **Uma fonte da verdade**: o ModuleScript `ReplicatedStorage.RoMetricsEvents` ([formato](/referencia/registro)) lista os eventos do jogo.
- **Eventos sem código**: selecione uma Part, prompt, detector ou Tool e clique em **Aplicar**. O plugin grava a tag `RoMetrics` e os [atributos `RM_*`](/referencia/atributos); o SDK faz o resto em runtime.
- **Começo guiado**: a aba Início instala o SDK do GitHub, cria o script de setup e mostra o que falta.
- **Código quando precisa**: snippets inserem `RoMetrics:LogCustomEvent(...)` e companhia já com os nomes do registro.
- **Tudo com Ctrl+Z**: marcações, edições do registro e snippets passam pelo `ChangeHistoryService`.
- **Sem dependências**: UI nativa do Studio, segue o tema claro/escuro, acento azul RoMetrics.

[Instalar](/plugin/instalacao) · [Abas e fluxo de uso](/plugin/abas)
