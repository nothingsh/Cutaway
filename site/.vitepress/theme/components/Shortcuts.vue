<script setup lang="ts">
// Every keyboard shortcut of Cutaway's menus, with a filter. Matches the menu bar of 1.2.
import { computed, ref } from 'vue'

import { useLocale } from '../locale'

interface Shortcut {
  action: string
  menu: string
  keys: string
}

const en: Shortcut[] = [
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
  { action: 'Cut', menu: 'Edit', keys: '⌘X' },
  { action: 'Copy', menu: 'Edit', keys: '⌘C' },
  { action: 'Paste', menu: 'Edit', keys: '⌘V' },
  { action: 'Select All', menu: 'Edit', keys: '⌘A' },
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

// The menu titles as the app shows them in Simplified Chinese.
const zh: Shortcut[] = [
  { action: '设置…', menu: 'Cutaway', keys: '⌘,' },
  { action: '隐藏 Cutaway', menu: 'Cutaway', keys: '⌘H' },
  { action: '隐藏其他', menu: 'Cutaway', keys: '⌥⌘H' },
  { action: '退出 Cutaway', menu: 'Cutaway', keys: '⌘Q' },
  { action: '打开…（存档）', menu: '文件', keys: '⌘O' },
  { action: '在 Xcode 中打开', menu: '文件', keys: '⌥⌘O' },
  { action: '存储存档…', menu: '文件', keys: '⌘S' },
  { action: '导出图层截图…', menu: '文件', keys: '⇧⌘E' },
  { action: '导出含子图层的截图…', menu: '文件', keys: '⌥⇧⌘E' },
  { action: '关闭窗口', menu: '文件', keys: '⌘W' },
  { action: '撤销一项修改', menu: '编辑', keys: '⌘Z' },
  { action: '重做一项修改', menu: '编辑', keys: '⇧⌘Z' },
  { action: '剪切', menu: '编辑', keys: '⌘X' },
  { action: '拷贝', menu: '编辑', keys: '⌘C' },
  { action: '粘贴', menu: '编辑', keys: '⌘V' },
  { action: '全选', menu: '编辑', keys: '⌘A' },
  { action: '查找…（过滤图层列表）', menu: '编辑', keys: '⌘F' },
  { action: '刷新', menu: '显示', keys: '⌘R' },
  { action: '刷新所选子树', menu: '显示', keys: '⇧⌘R' },
  { action: '环境 › 在浅色与深色之间切换', menu: '显示', keys: '⇧⌘A' },
  { action: '显示边栏', menu: '显示', keys: '⌃⌘S' },
  { action: '显示检查器', menu: '显示', keys: '⌥⌘I' },
  { action: '进入全屏幕', menu: '显示', keys: '⌃⌘F' },
  { action: '2D', menu: '显示', keys: '⌘1' },
  { action: '3D', menu: '显示', keys: '⌘2' },
  { action: '放大', menu: '显示', keys: '⌘=' },
  { action: '缩小', menu: '显示', keys: '⌘-' },
  { action: '重置视图', menu: '显示', keys: '⌘0' },
  { action: '显示隐藏的图层', menu: '显示', keys: '⇧⌘H' },
  { action: '边框 › 显示边框', menu: '显示', keys: '⇧⌘B' },
  { action: '显示约束的另一端', menu: '显示', keys: '⇧⌘K' },
  { action: '选择父图层', menu: '显示', keys: '⌘↑' },
  { action: '选择第一个子图层', menu: '显示', keys: '⌘↓' },
  { action: '聚焦于所选图层', menu: '显示', keys: '⌥⌘↓' },
  { action: '显示全部图层', menu: '显示', keys: '⌥⌘↑' },
  { action: '全部展开', menu: '显示', keys: '⌥⌘→' },
  { action: '全部折叠', menu: '显示', keys: '⌥⌘←' },
  { action: '最小化', menu: '窗口', keys: '⌘M' },
  { action: '显示 App 列表', menu: '窗口', keys: '⇧⌘0' }
]

const { t } = useLocale({
  en: {
    shortcuts: en,
    filter: 'Filter the shortcuts',
    placeholder: 'Filter by action, menu or keys (e.g. “shift cmd e”)',
    columns: ['Action', 'Menu', 'Keys'],
    none: (query: string) => `No shortcut matches “${query}”.`
  },
  'zh-Hans': {
    shortcuts: zh,
    filter: '过滤快捷键',
    placeholder: '按操作、菜单或按键过滤（例如“shift cmd e”）',
    columns: ['操作', '菜单', '按键'],
    none: (query: string) => `没有与“${query}”相符的快捷键。`
  }
})

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
  const shortcuts = t.value.shortcuts
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
      <span class="visually-hidden">{{ t.filter }}</span>
      <input v-model="query" type="search" :placeholder="t.placeholder" />
    </label>
    <table>
      <thead>
        <tr><th v-for="column in t.columns" :key="column">{{ column }}</th></tr>
      </thead>
      <tbody>
        <tr v-for="s in shown" :key="s.action">
          <td>{{ s.action }}</td>
          <td>{{ s.menu }}</td>
          <td><kbd>{{ s.keys }}</kbd></td>
        </tr>
        <tr v-if="shown.length === 0">
          <td colspan="3">{{ t.none(query) }}</td>
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
