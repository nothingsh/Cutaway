<script setup lang="ts">
// A session from the handshake to a stream and its end, as a sequence of frames.
import { computed } from 'vue'
import { useLocale } from '../locale'

const { t } = useLocale({
  en: {
    label:
      'The Client sends Hello and the Server answers with Hello, then the event AppStateChanged. Request 1, GetHierarchy, gets one Hierarchy. Request 2, GetLayerDetails, gets LayerDetailsChunk frames and then StreamEnd. Every frame carries the request_id of its request; 0 is the handshake and events.',
    notes: [
      'role Client, protocol 1.2',
      'role Server, its version, the app',
      'event: Active',
      'ordinary request',
      'exactly one response',
      'streaming request',
      'sequence 0, 1, …',
      'Completed, or Cancelled after a Cancel'
    ],
    caption: ['The number beside each arrow is the frame’s ', ': 0 for the handshake and events, then one per request, counted by the Client.']
  },
  'zh-Hans': {
    label:
      'Client 发送 Hello，Server 以 Hello 回答，随后发出事件 AppStateChanged。请求 1 是 GetHierarchy，得到一个 Hierarchy。请求 2 是 GetLayerDetails，得到若干 LayerDetailsChunk 帧，然后是 StreamEnd。每一帧都带着所属请求的 request_id；0 是握手和事件。',
    notes: [
      '角色 Client，协议 1.2',
      '角色 Server，它的版本，App',
      '事件：Active',
      '普通请求',
      '恰好一个回答',
      '流式请求',
      '序号 0、1、…',
      'Completed，或在 Cancel 之后为 Cancelled'
    ],
    caption: ['箭头旁的数字是这一帧的 ', '：握手和事件为 0，此后每个请求一个，由 Client 计数。']
  }
})

const frames = [
  { dir: 'right', id: '0', name: 'Hello' },
  { dir: 'left', id: '0', name: 'Hello' },
  { dir: 'left', id: '0', name: 'AppStateChanged' },
  { dir: 'right', id: '1', name: 'GetHierarchy' },
  { dir: 'left', id: '1', name: 'Hierarchy' },
  { dir: 'right', id: '2', name: 'GetLayerDetails' },
  { dir: 'left', id: '2', name: 'LayerDetailsChunk' },
  { dir: 'left', id: '2', name: 'StreamEnd' }
]
const rows = computed(() => frames.map((frame, index) => ({ ...frame, note: t.value.notes[index] })))
const top = 64
const step = 52
const height = top + frames.length * step + 10
</script>

<template>
  <figure class="exchange">
    <svg :viewBox="`0 0 680 ${height}`" role="img" :aria-label="t.label">
      <text class="head" x="120" y="26" text-anchor="middle">Cutaway (Client)</text>
      <text class="head" x="560" y="26" text-anchor="middle">CutawayServer</text>
      <line class="life" x1="120" y1="40" x2="120" :y2="height - 6" />
      <line class="life" x1="560" y1="40" x2="560" :y2="height - 6" />
      <g v-for="(row, index) in rows" :key="index">
        <line class="msg" :x1="row.dir === 'right' ? 124 : 556" :y1="top + index * step" :x2="row.dir === 'right' ? 550 : 130" :y2="top + index * step" />
        <path class="tip" :d="row.dir === 'right' ? `M556 ${top + index * step} l-10 -5 v10 z` : `M124 ${top + index * step} l10 -5 v10 z`" />
        <text class="name" x="340" :y="top + index * step - 8" text-anchor="middle">{{ row.name }}</text>
        <text class="note" x="340" :y="top + index * step + 17" text-anchor="middle">{{ row.note }}</text>
        <text class="id" :x="row.dir === 'right' ? 100 : 580" :y="top + index * step + 4" :text-anchor="row.dir === 'right' ? 'end' : 'start'">{{ row.id }}</text>
      </g>
    </svg>
    <figcaption>{{ t.caption[0] }}<code>request_id</code>{{ t.caption[1] }}</figcaption>
  </figure>
</template>

<style scoped>
.exchange {
  margin: 24px 0;
}

svg {
  display: block;
  width: 100%;
  height: auto;
  font-family: var(--vp-font-family-base);
}

.head {
  fill: var(--vp-c-text-1);
  font-size: 14px;
  font-weight: 650;
}

.life {
  stroke: var(--vp-c-divider);
  stroke-width: 2;
}

.msg {
  stroke: var(--vp-c-brand-1);
  stroke-width: 1.6;
}

.tip {
  fill: var(--vp-c-brand-1);
}

.name {
  fill: var(--vp-c-text-1);
  font-family: var(--vp-font-family-mono);
  font-size: 13px;
  font-weight: 600;
}

.note {
  fill: var(--vp-c-text-3);
  font-size: 11.5px;
}

.id {
  fill: var(--vp-c-text-2);
  font-family: var(--vp-font-family-mono);
  font-size: 12px;
}

figcaption {
  margin-top: 8px;
  color: var(--vp-c-text-2);
  font-size: 14px;
}
</style>
