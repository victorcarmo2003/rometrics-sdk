# Abas e fluxo de uso

A barra lateral segue a ordem do trabalho. O selo no topo mostra se o SDK está instalado no place.

| Aba | Para quê |
|---|---|
| **Início** | o que já está pronto neste place, a ação que resolve o que falta e o atalho para **Medir** |
| **Medir** | "o que você quer medir?": escolha o tipo (evento, funil, progressão, economia) e o assistente gera a linha de código e coloca no script certo |
| **Vendas** | acha quem atribui o `MarketplaceService.ProcessReceipt` e embrulha com `wrapProcessReceipt` em 1 clique (com prévia e Ctrl+Z) |
| **Eventos** | registro de eventos: busca, edição, props e onde cada evento é usado |
| **Ajustes** | endereço do servidor, Secret da chave, **Testar com o site**, **Enviar eventos de teste**, atualizar o SDK e as ferramentas avançadas |
| Avançado | **Marcar objeto (sem código)**, **Editor de funis** e **Conferir problemas** |

## Fluxo recomendado

1. **Início › Instalar do GitHub**: baixa o SDK da última release para `ReplicatedStorage.RoMetrics`.
2. **Ajustes**: confira o endereço do servidor e guarde a chave no Secret `rometrics_key`.
3. **Vendas**: embrulhe o `ProcessReceipt` do seu jogo (se ele vende developer products).
4. **Medir**: crie os eventos que importam e deixe o assistente colocar o código.
5. **Ajustes › Testar com o site**: cole o código do painel (Configurações › Jogos › Testar conexão). Use **Enviar eventos de teste** para ver como os eventos chegam sem dar Play, depois dê **Play** para o teste real.
6. Antes de publicar: **Conferir problemas**.

## Renomear eventos

Renomear atualiza o `RM_Event` de todas as instâncias marcadas (com Ctrl+Z). Ocorrências em scripts são **listadas** no diálogo de confirmação, mas não reescritas: ajuste o código você mesmo.

## Registros grandes

A aba Eventos mostra até 200 eventos por tipo; o restante aparece pela busca.
