<script setup lang="ts">
// What a build of the host app contains of CutawayServer, by configuration.
const columns = [
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
] as const
</script>

<template>
  <div class="builds" role="table" aria-label="What each build contains of CutawayServer">
    <div v-for="column in columns" :key="column.title" class="column" role="rowgroup">
      <b role="columnheader">{{ column.title }}</b>
      <span class="when">{{ column.when }}</span>
      <ul>
        <li v-for="[part, included] in column.parts" :key="part" :class="{ out: !included }" role="cell">
          <span class="mark" aria-hidden="true">{{ included ? '✓' : '—' }}</span>
          <span><span class="visually-hidden">{{ included ? 'Included: ' : 'Left out: ' }}</span>{{ part }}</span>
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
