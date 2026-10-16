# Contribuindo

Issues e pull requests são bem-vindos.

- **Bugs**: abra uma issue com o trecho do Output (com `debug = true`) e os passos para reproduzir. Nunca cole sua chave `rmk_live_...`.
- **Código Luau**: `--!strict`, tabs, nenhuma função pública pode lançar erro para o código do jogo (`pcall` nas bordas). Rode os testes e o lint antes do PR:

  ```bash
  cd sdk/roblox && lune run tests/run.luau
  lune run plugin/tools/run-tests.luau
  selene sdk/roblox/src plugin/src
  ```

- **Mudou a API?** Atualize, no mesmo PR:
  - `docs/referencia/*` e a página do guia afetada;
  - `docs/public/rometrics-sdk.ai.md` (referência para IA: assinaturas, regras e erros comuns);
  - `docs/changelog.md`.
- **Builds `.rbxm`**: regenere `sdk/roblox/dist/RoMetrics.rbxm` e `plugin/dist/RoMetricsPlugin.rbxm` com `rojo build` quando o código mudar.

Releases: crie uma tag `vX.Y.Z`; o workflow anexa os dois `.rbxm` à release.
