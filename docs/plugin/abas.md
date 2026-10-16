# Abas e fluxo de uso

| Aba | Esquerda | Principal |
|---|---|---|
| **Eventos** | árvore com busca, agrupada por tipo (`custom`, `funnel`, `progression`, `economy`) | descrição, props, gatilho, onde é usado (instâncias com tag e linhas de scripts), Novo/Salvar/Renomear/Remover |
| **Rastrear** | instâncias com a tag `RoMetrics` (clique seleciona no Explorer) | seleção atual → evento, gatilho, valor, cooldown, uma vez, props → **Aplicar** / **Remover rastreio**; "Destacar rastreados" |
| **Snippets** | lista de snippets | prévia do código + evento alvo → **Inserir no script selecionado** ou **Novo Script** |
| **Fluxos** | funis do registro | editor de passos (arrastar, renomear, ligar evento ao passo) e diagrama passo → passo |
| **Validação** | — | erros e avisos com atalho para o evento, instância ou script |
| **Config** | — | endpoint, nome do Secret, caminho do SDK, **Testar conexão**, URL do dashboard |

## Fluxo recomendado

1. **Config**: confira o endpoint e o nome do Secret (padrão `rometrics_key`). O caminho do SDK é detectado sozinho.
2. **Snippets → Setup (init + Secret) → Novo Script**: cria `ServerScriptService.RoMetricsSetup` com `init` e `wrapProcessReceipt`.
3. **Eventos → Novo**: registre os eventos com nome, tipo, descrição e props.
4. Eventos do mapa: selecione a instância → **Rastrear** → evento, gatilho e cooldown → **Aplicar**.
5. Eventos de código: **Snippets** → escolha o snippet e o evento → insere no script selecionado.
6. Funis: **Fluxos** → crie o funil, ordene os passos e ligue eventos a cada passo.
7. Antes de publicar: **Validação** (nomes inválidos, duplicados, eventos usados mas não registrados, tags órfãs, gatilhos sem alvo).

## Renomear eventos

Renomear atualiza o `RM_Event` de todas as instâncias marcadas (com Ctrl+Z). Ocorrências em scripts são **listadas** no diálogo de confirmação, mas não reescritas: ajuste o código você mesmo.

## Registros grandes

A aba Eventos mostra até 200 eventos por tipo; o restante aparece pela busca.
