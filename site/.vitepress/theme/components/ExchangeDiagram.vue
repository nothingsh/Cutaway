<script setup lang="ts">
// A session from the handshake to a stream and its end, as a sequence of frames.
const rows = [
  { dir: 'right', id: '0', name: 'Hello', note: 'role Client, protocol 1.2' },
  { dir: 'left', id: '0', name: 'Hello', note: 'role Server, its version, the app' },
  { dir: 'left', id: '0', name: 'AppStateChanged', note: 'event: Active' },
  { dir: 'right', id: '1', name: 'GetHierarchy', note: 'ordinary request' },
  { dir: 'left', id: '1', name: 'Hierarchy', note: 'exactly one response' },
  { dir: 'right', id: '2', name: 'GetLayerDetails', note: 'streaming request' },
  { dir: 'left', id: '2', name: 'LayerDetailsChunk', note: 'sequence 0, 1, …' },
  { dir: 'left', id: '2', name: 'StreamEnd', note: 'Completed, or Cancelled after a Cancel' }
]
const top = 64
const step = 52
const height = top + rows.length * step + 10
</script>

<template>
  <figure class="exchange">
    <svg :viewBox="`0 0 680 ${height}`" role="img" aria-label="The Client sends Hello and the Server answers with Hello, then the event AppStateChanged. Request 1, GetHierarchy, gets one Hierarchy. Request 2, GetLayerDetails, gets LayerDetailsChunk frames and then StreamEnd. Every frame carries the request_id of its request; 0 is the handshake and events.">
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
    <figcaption>The number beside each arrow is the frame’s <code>request_id</code>: 0 for the handshake and events, then one per request, counted by the Client.</figcaption>
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
