<script setup lang="ts">
// The bytes of one frame: a 4-byte little-endian length, then an ordinary FlatBuffer.
</script>

<template>
  <figure class="frame-diagram">
    <svg viewBox="0 0 680 150" role="img" aria-label="A frame: a 4-byte little-endian length N, then N bytes holding one FlatBuffer. The FlatBuffer starts with the offset of its root table, then the file identifier CTWY, then the Frame table with request_id and body.">
      <g class="t">
        <text x="10" y="22">4 bytes</text>
        <text x="150" y="22">N bytes (at most 256 MiB): one ordinary FlatBuffer</text>
      </g>
      <rect class="len" x="10" y="34" width="130" height="56" rx="6" />
      <text class="in" x="75" y="58" text-anchor="middle">N</text>
      <text class="in s" x="75" y="77" text-anchor="middle">little-endian</text>
      <rect class="fb" x="150" y="34" width="110" height="56" rx="6" />
      <text class="in" x="205" y="58" text-anchor="middle">root offset</text>
      <text class="in s" x="205" y="77" text-anchor="middle">bytes 1–4</text>
      <rect class="fb" x="270" y="34" width="110" height="56" rx="6" />
      <text class="in mono" x="325" y="58" text-anchor="middle">CTWY</text>
      <text class="in s" x="325" y="77" text-anchor="middle">bytes 5–8</text>
      <rect class="fb" x="390" y="34" width="280" height="56" rx="6" />
      <text class="in mono" x="530" y="58" text-anchor="middle">Frame { request_id, body }</text>
      <text class="in s" x="530" y="77" text-anchor="middle">body: Hello, GetHierarchy, Hierarchy, …</text>
      <g class="t">
        <text x="10" y="122">N does not count its own 4 bytes. This is not FlatBuffers’ size-prefixed format:</text>
        <text x="10" y="142">the buffer after the length is exactly what any FlatBuffers runtime builds.</text>
      </g>
    </svg>
  </figure>
</template>

<style scoped>
.frame-diagram {
  margin: 24px 0;
}

svg {
  display: block;
  width: 100%;
  height: auto;
  font-family: var(--vp-font-family-base);
}

.t text {
  fill: var(--vp-c-text-2);
  font-size: 13px;
}

.len {
  fill: var(--vp-c-brand-soft);
  stroke: var(--vp-c-brand-1);
}

.fb {
  fill: var(--vp-c-bg-soft);
  stroke: var(--vp-c-divider);
}

.in {
  fill: var(--vp-c-text-1);
  font-size: 14px;
  font-weight: 600;
}

.in.s {
  fill: var(--vp-c-text-3);
  font-size: 11.5px;
  font-weight: 400;
}

.mono {
  font-family: var(--vp-font-family-mono);
  font-size: 13px;
}
</style>
