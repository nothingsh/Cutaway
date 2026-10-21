<script setup lang="ts">
// The bytes of one frame: a 4-byte little-endian length, then an ordinary FlatBuffer.
import { useLocale } from '../locale'

const { t } = useLocale({
  en: {
    label:
      'A frame: a 4-byte little-endian length N, then N bytes holding one FlatBuffer. The FlatBuffer starts with the offset of its root table, then the file identifier CTWY, then the Frame table with request_id and body.',
    length: '4 bytes',
    buffer: 'N bytes (at most 256 MiB): one ordinary FlatBuffer',
    littleEndian: 'little-endian',
    root: 'root offset',
    bytes: (range: string) => `bytes ${range}`,
    notes: [
      'N does not count its own 4 bytes. This is not FlatBuffers’ size-prefixed format:',
      'the buffer after the length is exactly what any FlatBuffers runtime builds.'
    ]
  },
  'zh-Hans': {
    label:
      '一帧：4 字节小端序的长度 N，然后是 N 字节，存放一个 FlatBuffer。FlatBuffer 以根表的偏移开头，然后是文件标识 CTWY，然后是带 request_id 和 body 的 Frame 表。',
    length: '4 字节',
    buffer: 'N 字节（至多 256 MiB）：一个普通的 FlatBuffer',
    littleEndian: '小端序',
    root: '根表偏移',
    bytes: (range: string) => `第 ${range} 字节`,
    notes: [
      'N 不计它自己的 4 字节。这不是 FlatBuffers 带长度前缀的格式：',
      '长度之后的缓冲区与任何 FlatBuffers 运行库构建出的完全相同。'
    ]
  }
})
</script>

<template>
  <figure class="frame-diagram">
    <svg viewBox="0 0 680 150" role="img" :aria-label="t.label">
      <g class="t">
        <text x="10" y="22">{{ t.length }}</text>
        <text x="150" y="22">{{ t.buffer }}</text>
      </g>
      <rect class="len" x="10" y="34" width="130" height="56" rx="6" />
      <text class="in" x="75" y="58" text-anchor="middle">N</text>
      <text class="in s" x="75" y="77" text-anchor="middle">{{ t.littleEndian }}</text>
      <rect class="fb" x="150" y="34" width="110" height="56" rx="6" />
      <text class="in" x="205" y="58" text-anchor="middle">{{ t.root }}</text>
      <text class="in s" x="205" y="77" text-anchor="middle">{{ t.bytes('1–4') }}</text>
      <rect class="fb" x="270" y="34" width="110" height="56" rx="6" />
      <text class="in mono" x="325" y="58" text-anchor="middle">CTWY</text>
      <text class="in s" x="325" y="77" text-anchor="middle">{{ t.bytes('5–8') }}</text>
      <rect class="fb" x="390" y="34" width="280" height="56" rx="6" />
      <text class="in mono" x="530" y="58" text-anchor="middle">Frame { request_id, body }</text>
      <text class="in s" x="530" y="77" text-anchor="middle">body: Hello, GetHierarchy, Hierarchy, …</text>
      <g class="t">
        <text x="10" y="122">{{ t.notes[0] }}</text>
        <text x="10" y="142">{{ t.notes[1] }}</text>
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
