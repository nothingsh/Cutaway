<script setup lang="ts">
// A short silent video that loops: public/media/<name>.mp4, with <name>.jpg as its poster.
// It plays by itself only when the viewer has not asked for reduced motion; otherwise it shows
// the poster and the player's controls. A placeholder stands in until the video exists.
import { computed, onMounted, ref } from 'vue'
import { withBase } from 'vitepress'
import { data } from '../media.data'
import { useLocale } from '../locale'

const props = defineProps<{ name: string; alt: string }>()

const ready = computed(() => data.files.includes(`${props.name}.mp4`))
const poster = computed(() => (data.files.includes(`${props.name}.jpg`) ? withBase(`/media/${props.name}.jpg`) : undefined))
const moves = ref(false)
const { t } = useLocale({ en: 'Video', 'zh-Hans': '视频' })

onMounted(() => {
  moves.value = !window.matchMedia('(prefers-reduced-motion: reduce)').matches
})
</script>

<template>
  <div class="loop">
    <video
      v-if="ready"
      :src="withBase(`/media/${name}.mp4`)"
      :poster="poster"
      :autoplay="moves"
      :controls="!moves"
      :aria-label="alt"
      muted
      loop
      playsinline
      preload="metadata"
    ></video>
    <div v-else class="placeholder" role="img" :aria-label="alt">
      <b>{{ t }} · {{ name }}</b>
      <span>{{ alt }}</span>
    </div>
  </div>
</template>

<style scoped>
.loop video {
  display: block;
  width: 100%;
  height: auto;
  aspect-ratio: 16 / 10;
  border-radius: 12px;
  box-shadow: var(--cw-shadow);
  background: var(--cw-soft);
}

.placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  aspect-ratio: 16 / 10;
  padding: 24px;
  box-sizing: border-box;
  border: 1px dashed var(--vp-c-divider);
  border-radius: 12px;
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
