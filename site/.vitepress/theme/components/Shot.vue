<script setup lang="ts">
// A screenshot in light and dark: public/media/<name>-light.png and <name>-dark.png, swapped
// with the site's appearance. Until both exist it is a labelled placeholder, so that a page can
// be written before its images are made (public/media/README.md lists them).
import { computed } from 'vue'
import { withBase } from 'vitepress'
import { data } from '../media.data'

const props = defineProps<{ name: string; alt: string; width?: number; height?: number }>()

const light = computed(() => `${props.name}-light.png`)
const dark = computed(() => `${props.name}-dark.png`)
const ready = computed(() => data.files.includes(light.value) && data.files.includes(dark.value))
</script>

<template>
  <figure class="shot">
    <template v-if="ready">
      <img class="light-only" :src="withBase(`/media/${light}`)" :alt="alt" :width="width" :height="height" loading="lazy" decoding="async" />
      <img class="dark-only" :src="withBase(`/media/${dark}`)" :alt="alt" :width="width" :height="height" loading="lazy" decoding="async" />
    </template>
    <div v-else class="placeholder" role="img" :aria-label="alt">
      <b>Screenshot · {{ name }}</b>
      <span>{{ alt }}</span>
    </div>
  </figure>
</template>

<style scoped>
.shot {
  margin: 20px 0;
}

.shot img {
  display: block;
  max-width: 100%;
  height: auto;
  border-radius: 10px;
  box-shadow: var(--cw-shadow);
}

.dark .light-only,
html:not(.dark) .dark-only {
  display: none;
}

.placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  min-height: 200px;
  padding: 24px;
  border: 1px dashed var(--vp-c-divider);
  border-radius: 10px;
  background: var(--cw-soft);
  color: var(--vp-c-text-2);
  font-size: 14px;
  text-align: center;
}

.placeholder b {
  font-size: 11px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--vp-c-text-3);
}
</style>
