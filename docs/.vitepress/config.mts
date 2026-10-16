import { defineConfig } from 'vitepress';

const REPO = 'https://github.com/victorcarmo2003/rometrics-sdk';

export default defineConfig({
  lang: 'pt-BR',
  title: 'RoMetrics SDK',
  description: 'Analytics em tempo real para jogos Roblox: SDK Luau e plugin do Roblox Studio.',
  base: '/rometrics-sdk/',
  cleanUrls: true,
  lastUpdated: true,
  appearance: 'force-dark',
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/rometrics-sdk/logo.svg' }],
    ['meta', { name: 'theme-color', content: '#08090B' }],
    ['meta', { property: 'og:title', content: 'RoMetrics SDK' }],
    ['meta', { property: 'og:description', content: 'Analytics em tempo real para jogos Roblox.' }],
    ['link', { rel: 'alternate', type: 'text/markdown', title: 'Referência para IA', href: '/rometrics-sdk/rometrics-sdk.ai.md' }],
  ],
  themeConfig: {
    logo: '/logo.svg',
    siteTitle: 'RoMetrics SDK',
    nav: [
      { text: 'Guia', link: '/guia/comecando', activeMatch: '/guia/' },
      { text: 'Referência', link: '/referencia/sdk', activeMatch: '/referencia/' },
      { text: 'Plugin', link: '/plugin/', activeMatch: '/plugin/' },
      { text: 'Para IA', link: '/ia' },
      {
        text: 'v0.1.0',
        items: [
          { text: 'Downloads (.rbxm)', link: `${REPO}/releases/latest` },
          { text: 'Changelog', link: '/changelog' },
        ],
      },
    ],
    sidebar: {
      '/guia/': [
        {
          text: 'Primeiros passos',
          items: [
            { text: 'Começando', link: '/guia/comecando' },
            { text: 'Instalação', link: '/guia/instalacao' },
            { text: 'Chave e Secrets', link: '/guia/chave-e-secrets' },
            { text: 'Configuração', link: '/guia/configuracao' },
          ],
        },
        {
          text: 'Rastreando',
          items: [
            { text: 'Eventos', link: '/guia/eventos' },
            { text: 'Compras', link: '/guia/compras' },
            { text: 'Eventos sem código (tags)', link: '/guia/tags' },
            { text: 'Atribuição (deep links)', link: '/guia/atribuicao' },
            { text: 'Plataforma do jogador', link: '/guia/plataforma' },
          ],
        },
        {
          text: 'Operação',
          items: [
            { text: 'Testando no Studio', link: '/guia/testando-no-studio' },
            { text: 'Limites e confiabilidade', link: '/guia/limites' },
            { text: 'Problemas comuns', link: '/guia/problemas-comuns' },
          ],
        },
      ],
      '/referencia/': [
        {
          text: 'Referência',
          items: [
            { text: 'API do módulo RoMetrics', link: '/referencia/sdk' },
            { text: 'Opções do init', link: '/referencia/opcoes' },
            { text: 'Atributos de tag (RM_*)', link: '/referencia/atributos' },
            { text: 'Registro de eventos', link: '/referencia/registro' },
            { text: 'Dados enviados', link: '/referencia/dados-enviados' },
          ],
        },
      ],
      '/plugin/': [
        {
          text: 'Plugin do Studio',
          items: [
            { text: 'Visão geral', link: '/plugin/' },
            { text: 'Instalação', link: '/plugin/instalacao' },
            { text: 'Abas e fluxo de uso', link: '/plugin/abas' },
          ],
        },
      ],
    },
    socialLinks: [{ icon: 'github', link: REPO }],
    editLink: { pattern: `${REPO}/edit/main/docs/:path`, text: 'Editar esta página no GitHub' },
    search: {
      provider: 'local',
      options: {
        translations: {
          button: { buttonText: 'Buscar', buttonAriaLabel: 'Buscar' },
          modal: {
            noResultsText: 'Nada encontrado para',
            resetButtonTitle: 'Limpar',
            footer: { selectText: 'abrir', navigateText: 'navegar', closeText: 'fechar' },
          },
        },
      },
    },
    outline: { level: [2, 3], label: 'Nesta página' },
    docFooter: { prev: 'Anterior', next: 'Próxima' },
    lastUpdated: { text: 'Atualizado em' },
    returnToTopLabel: 'Voltar ao topo',
    sidebarMenuLabel: 'Menu',
    darkModeSwitchLabel: 'Tema',
    footer: { message: 'Código sob licença MIT.', copyright: '© 2026 RoMetrics' },
  },
});
