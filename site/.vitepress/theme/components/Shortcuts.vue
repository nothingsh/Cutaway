<script setup lang="ts">
// Every keyboard shortcut of Cutaway's menus, with a filter. Matches the menu bar of 1.2.
import { computed, ref } from 'vue'

interface Shortcut {
  action: string
  menu: string
  keys: string
}

const shortcuts: Shortcut[] = [
  { action: 'Settings…', menu: 'Cutaway', keys: '⌘,' },
  { action: 'Hide Cutaway', menu: 'Cutaway', keys: '⌘H' },
  { action: 'Hide Others', menu: 'Cutaway', keys: '⌥⌘H' },
  { action: 'Quit Cutaway', menu: 'Cutaway', keys: '⌘Q' },
  { action: 'Open… (an archive)', menu: 'File', keys: '⌘O' },
  { action: 'Open in Xcode', menu: 'File', keys: '⌥⌘O' },
  { action: 'Save Archive…', menu: 'File', keys: '⌘S' },
  { action: 'Export Layer Screenshot…', menu: 'File', keys: '⇧⌘E' },
  { action: 'Export Screenshot with Sublayers…', menu: 'File', keys: '⌥⇧⌘E' },
  { action: 'Close Window', menu: 'File', keys: '⌘W' },
  { action: 'Undo a change', menu: 'Edit', keys: '⌘Z' },
  { action: 'Redo a change', menu: 'Edit', keys: '⇧⌘Z' },
  { action: 'Find… (filter the layer list)', menu: 'Edit', keys: '⌘F' },
  { action: 'Refresh', menu: 'View', keys: '⌘R' },
  { action: 'Refresh Selected Subtree', menu: 'View', keys: '⇧⌘R' },
  { action: 'Environment › Toggle Light and Dark', menu: 'View', keys: '⇧⌘A' },
  { action: 'Show Sidebar', menu: 'View', keys: '⌃⌘S' },
  { action: 'Show Inspector', menu: 'View', keys: '⌥⌘I' },
  { action: 'Enter Full Screen', menu: 'View', keys: '⌃⌘F' },
  { action: '2D', menu: 'View', keys: '⌘1' },
  { action: '3D', menu: 'View', keys: '⌘2' },
  { action: 'Zoom In', menu: 'View', keys: '⌘=' },
  { action: 'Zoom Out', menu: 'View', keys: '⌘-' },
  { action: 'Reset View', menu: 'View', keys: '⌘0' },
  { action: 'Show Hidden Layers', menu: 'View', keys: '⇧⌘H' },
  { action: 'Borders › Show Borders', menu: 'View', keys: '⇧⌘B' },
  { action: 'Show Constraint Ends', menu: 'View', keys: '⇧⌘K' },
  { action: 'Select Parent Layer', menu: 'View', keys: '⌘↑' },
  { action: 'Select First Child Layer', menu: 'View', keys: '⌘↓' },
  { action: 'Focus on Selected Layer', menu: 'View', keys: '⌥⌘↓' },
  { action: 'Show All Layers', menu: 'View', keys: '⌥⌘↑' },
  { action: 'Expand All', menu: 'View', keys: '⌥⌘→' },
  { action: 'Collapse All', menu: 'View', keys: '⌥⌘←' },
  { action: 'Minimize', menu: 'Window', keys: '⌘M' },
  { action: 'Show App List', menu: 'Window', keys: '⇧⌘0' }
]

const query = ref('')

// Matches the action, the menu, or the keys as typed: "cmd shift e" or "⇧⌘E".
const words: [RegExp, string][] = [
  [/\b(cmd|command)\b/g, '⌘'],
  [/\b(shift)\b/g, '⇧'],
  [/\b(opt|option|alt)\b/g, '⌥'],
  [/\b(ctrl|control)\b/g, '⌃']
]

const shown = computed(() => {
  const text = query.value.trim().toLowerCase()
  if (!text) return shortcuts
  let symbols = text
  for (const [pattern, symbol] of words) symbols = symbols.replace(pattern, symbol)
  symbols = symbols.replace(/\s+/g, '')
  return shortcuts.filter((s) => {
    const haystack = `${s.action} ${s.menu}`.toLowerCase()
    const keys = s.keys.toLowerCase()
    return haystack.includes(text) || [...symbols].every((c) => keys.includes(c))
  })
})
</script>

<template>
  <div class="shortcuts">
    <label class="filter">
      <span class="visually-hidden">Filter the shortcuts</span>
      <input v-model="query" type="search" placeholder="Filter by action, menu or keys (e.g. “shift cmd e”)" />
    </label>
    <table>
      <thead>
        <tr><th>Action</th><th>Menu</th><th>Keys</th></tr>
      </thead>
      <tbody>
        <tr v-for="s in shown" :key="s.action">
          <td>{{ s.action }}</td>
          <td>{{ s.menu }}</td>
          <td><kbd>{{ s.keys }}</kbd></td>
        </tr>
        <tr v-if="shown.length === 0">
          <td colspan="3">No shortcut matches “{{ query }}”.</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.filter input {
  width: 100%;
  height: 40px;
  margin: 12px 0 4px;
  padding: 0 12px;
  box-sizing: border-box;
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  background: var(--vp-c-bg-alt);
  color: var(--vp-c-text-1);
  font-size: 15px;
}

.filter input:focus {
  outline: 2px solid var(--vp-c-brand-1);
  outline-offset: 1px;
}

.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip: rect(0 0 0 0);
}

.shortcuts table {
  display: table;
  width: 100%;
}
</style>
