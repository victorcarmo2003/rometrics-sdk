<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { withBase } from 'vitepress';

const FILE = '/rometrics-sdk.ai.md';
const url = withBase(FILE);
const text = ref('');
const status = ref<'loading' | 'ready' | 'error'>('loading');
const copied = ref(false);

onMounted(async () => {
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(String(res.status));
    text.value = await res.text();
    status.value = 'ready';
  } catch {
    status.value = 'error';
  }
});

const absoluteUrl = computed(() => (typeof window === 'undefined' ? url : new URL(url, window.location.href).href));
const lines = computed(() => (text.value ? text.value.split('\n').length : 0));
const approxTokens = computed(() => Math.round(text.value.length / 4 / 100) * 100);

async function copy() {
  if (!text.value) return;
  try {
    await navigator.clipboard.writeText(text.value);
    copied.value = true;
    setTimeout(() => (copied.value = false), 2000);
  } catch {
    copied.value = false;
  }
}
</script>

<template>
  <div class="ai-doc">
    <div class="ai-doc__bar">
      <div class="ai-doc__meta">
        <strong>rometrics-sdk.ai.md</strong>
        <span v-if="status === 'ready'">{{ lines }} linhas · ~{{ approxTokens.toLocaleString('pt-BR') }} tokens</span>
        <span v-else-if="status === 'loading'">carregando…</span>
        <span v-else>não foi possível carregar o arquivo</span>
      </div>
      <div class="ai-doc__actions">
        <button class="ai-doc__btn ai-doc__btn--primary" :disabled="status !== 'ready'" @click="copy">
          {{ copied ? 'Copiado ✓' : 'Copiar tudo' }}
        </button>
        <a class="ai-doc__btn" :href="url" download="rometrics-sdk.ai.md">Baixar .md</a>
        <a class="ai-doc__btn" :href="url" target="_blank" rel="noopener">Abrir cru</a>
      </div>
    </div>
    <p class="ai-doc__url">
      URL direta: <code>{{ absoluteUrl }}</code>
    </p>
    <pre v-if="status === 'ready'" class="ai-doc__preview"><code>{{ text }}</code></pre>
  </div>
</template>

<style scoped>
.ai-doc {
  margin-top: 16px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  background: var(--vp-c-bg-soft);
  overflow: hidden;
}
.ai-doc__bar {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  align-items: center;
  justify-content: space-between;
  padding: 14px 16px;
  border-bottom: 1px solid var(--vp-c-divider);
}
.ai-doc__meta {
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-size: 13px;
  color: var(--vp-c-text-3);
}
.ai-doc__meta strong {
  color: var(--vp-c-text-1);
  font-family: var(--vp-font-family-mono);
  font-size: 13px;
}
.ai-doc__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.ai-doc__btn {
  display: inline-flex;
  align-items: center;
  height: 34px;
  padding: 0 14px;
  border-radius: 8px;
  border: 1px solid var(--vp-c-divider);
  background: var(--vp-c-bg);
  color: var(--vp-c-text-1);
  font-size: 13px;
  font-weight: 500;
  text-decoration: none !important;
  cursor: pointer;
}
.ai-doc__btn:hover {
  border-color: var(--vp-c-brand-2);
}
.ai-doc__btn--primary {
  background: var(--vp-c-brand-2);
  border-color: var(--vp-c-brand-2);
  color: #fff;
}
.ai-doc__btn:disabled {
  opacity: 0.5;
  cursor: default;
}
.ai-doc__url {
  margin: 0 !important;
  padding: 10px 16px;
  font-size: 13px;
  color: var(--vp-c-text-3);
  border-bottom: 1px solid var(--vp-c-divider);
  word-break: break-all;
}
.ai-doc__preview {
  margin: 0;
  max-height: 420px;
  overflow: auto;
  padding: 16px;
  font-size: 12px;
  line-height: 1.55;
  white-space: pre-wrap;
  background: var(--vp-c-bg);
}
</style>
