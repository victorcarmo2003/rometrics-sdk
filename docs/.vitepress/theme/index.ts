import DefaultTheme from 'vitepress/theme';
import type { Theme } from 'vitepress';
import AiDoc from './components/AiDoc.vue';
import './custom.css';

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('AiDoc', AiDoc);
  },
} satisfies Theme;
