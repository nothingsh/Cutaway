<script setup lang="ts">
// What a build of the host app contains of CutawayServer, by configuration.
import { useLocale } from '../locale'

const { t } = useLocale({
  en: {
    label: 'What each build contains of CutawayServer',
    included: 'Included: ',
    leftOut: 'Left out: ',
    columns: [
      {
        title: 'Debug',
        when: 'The configuration defines DEBUG',
        parts: [
          ['start()', true],
          ['The server: listening, capturing', true],
          ['Network, the protocol’s encoding', true],
          ['Your describe(…) registrations', true]
        ]
      },
      {
        title: 'Release',
        when: 'No DEBUG, trait off (the default)',
        parts: [
          ['start(), an empty function', true],
          ['The server: listening, capturing', false],
          ['Network, the protocol’s encoding', false],
          ['Your describe(…) registrations: do nothing', true]
        ]
      },
      {
        title: 'ReleaseEnabled',
        when: 'The package trait is on: every configuration',
        parts: [
          ['start()', true],
          ['The server: listening, capturing', true],
          ['Network, the protocol’s encoding', true],
          ['Your describe(…) registrations', true]
        ]
      }
    ]
  },
  'zh-Hans': {
    label: '各种构建里包含 CutawayServer 的哪些部分',
    included: '包含：',
    leftOut: '不含：',
    columns: [
      {
        title: 'Debug',
        when: '配置定义了 DEBUG',
        parts: [
          ['start()', true],
          ['服务端：监听、截取', true],
          ['Network 与协议的编码', true],
          ['你的 describe(…) 登记', true]
        ]
      },
      {
        title: 'Release',
        when: '没有 DEBUG，trait 关闭（默认）',
        parts: [
          ['start()，一个空函数', true],
          ['服务端：监听、截取', false],
          ['Network 与协议的编码', false],
          ['你的 describe(…) 登记：什么也不做', true]
        ]
      },
      {
        title: 'ReleaseEnabled',
        when: '打开了包的 trait：所有配置',
        parts: [
          ['start()', true],
          ['服务端：监听、截取', true],
          ['Network 与协议的编码', true],
          ['你的 describe(…) 登记', true]
        ]
      }
    ]
  }
} as const)
</script>

<template>
  <div class="builds" role="table" :aria-label="t.label">
    <div v-for="column in t.columns" :key="column.title" class="column" role="rowgroup">
      <b role="columnheader">{{ column.title }}</b>
      <span class="when">{{ column.when }}</span>
      <ul>
        <li v-for="[part, included] in column.parts" :key="part" :class="{ out: !included }" role="cell">
          <span class="mark" aria-hidden="true">{{ included ? '✓' : '—' }}</span>
          <span><span class="visually-hidden">{{ included ? t.included : t.leftOut }}</span>{{ part }}</span>
        </li>
      </ul>
    </div>
  </div>
</template>

<style scoped>
.builds {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 12px;
  margin: 20px 0;
}

.column {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 16px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  background: var(--vp-c-bg-soft);
}

.column b {
  font-size: 15px;
}

.when {
  color: var(--vp-c-text-3);
  font-size: 13px;
}

ul {
  margin: 8px 0 0 !important;
  padding: 0 !important;
  list-style: none !important;
}

li {
  display: flex;
  gap: 8px;
  margin: 4px 0 !important;
  font-size: 14px;
  line-height: 1.45;
}

.mark {
  flex: none;
  width: 14px;
  color: var(--vp-c-brand-1);
  font-weight: 700;
}

.out {
  color: var(--vp-c-text-3);
}

.out .mark {
  color: var(--vp-c-text-3);
}

.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip: rect(0 0 0 0);
}
</style>
