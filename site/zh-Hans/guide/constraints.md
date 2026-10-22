---
description: 查看所选视图的 Auto Layout 约束，看出哪些未生效，并找到每一条的另一端。
---

# 约束 {#constraints}

属性的“布局”一节最后列出指向所选视图的 Auto Layout 约束。本页说明怎样读它们，并顺着找到另一端。

## 读一条约束 {#read-a-constraint}

每条约束按 App 报告的样子写出：

```text
self.leading = UIView 的安全区域.leading + 16
```

`self` 是所选视图。另一端是一个带图标和名字的小块；它可以是另一个视图，也可以是一个布局参考线（安全区域、布局边距、可读内容、键盘）。优先级低于 1000 时显示优先级，有标识符时显示标识符。

- **未生效**的约束变淡，并带有标记。
- **UIKit 自己生成**的约束合成一行，例如“4 个来自 UIKit”。

在“布局”一节靠前的位置，Auto Layout 一行说明视图的布局是否有歧义，旁边是它的抗拉伸、抗压缩和固有尺寸。

<Shot name="guide-constraints-list" alt="一个视图的约束列表，指针指着其中一条，预览里标出了它的另一端。" />

## 找到另一端 {#find-the-other-end}

- **指向**一条约束，预览里就会标出它的另一端。
- **点按**另一端的小块，就会选中那个视图。
- **显示 › 显示约束的另一端**（<kbd>⇧⌘K</kbd>）一次标出所有约束的另一端。预览下方的边框菜单里也有这一项，叫**约束的另一端**。

## 下一步 {#next}

<NextSteps :items="[
  { title: '测距', text: '核对约束产生的距离。', link: '/zh-Hans/guide/measuring' },
  { title: '属性', text: '在运行中的 App 里修改 frame 或边距。', link: '/zh-Hans/guide/attributes' }
]" />
