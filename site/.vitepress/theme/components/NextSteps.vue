<script setup lang="ts">
// Cards that lead on from the end of a page: [{ title, text, link }].
import { withBase } from 'vitepress'

defineProps<{ items: { title: string; text: string; link: string }[] }>()
</script>

<template>
  <div class="next-steps">
    <a v-for="item in items" :key="item.link" class="card" :href="withBase(item.link)">
      <b>{{ item.title }}</b>
      <span>{{ item.text }}</span>
    </a>
  </div>
</template>

<style scoped>
.next-steps {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 12px;
  margin: 16px 0;
}

.vp-doc .card {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 16px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  color: var(--vp-c-text-2);
  font-size: 14px;
  line-height: 1.5;
  text-decoration: none;
  transition: border-color 0.2s;
}

.vp-doc .card:hover {
  border-color: var(--vp-c-brand-1);
}

.card b {
  color: var(--vp-c-text-1);
  font-size: 15px;
}
</style>
