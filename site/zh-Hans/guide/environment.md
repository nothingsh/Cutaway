---
description: 从 Cutaway 改写 App 的外观、文字大小、布局方向和尺寸类别，在预览里看到结果。
---

# 环境 {#environment}

在深色模式下、以更大的文字或从右到左查看你的界面，不用改模拟器或设备的设置。

<div class="facts">
  <Badge type="info" text="需要 CutawayServer 1.2" />
</div>

## 改写环境 {#override-the-environment}

1. 点按工具栏里 2D 和 3D 左边的**环境**。
2. 选一个值。外观、布局方向和尺寸类别是分段控件：

| 设置 | 可选的值 |
|---|---|
| **外观** | App 自己的、浅色、深色 |
| **文字大小** | 勾选**改写**，然后在滑块上从 XS 到 AX5 的十二种大小中选一种；取消勾选则用 App 自己的 |
| **布局方向** | App 自己的、从左到右、从右到左 |
| **水平尺寸类别** | App 自己的、Compact、Regular |
| **垂直尺寸类别** | App 自己的、Compact、Regular |

每项设置下面的“现在：…”写着 App 此刻的值。只要有任何一项被改写，“环境”按钮就会带上强调色。**复原**把每项设置都还给 App 自己的。

**显示 › 环境**里有同样的设置（尺寸类别在**尺寸类别**下），**显示 › 环境 › 在浅色与深色之间切换**（<kbd>⇧⌘A</kbd>）可以用键盘切换外观。

<Shot name="guide-environment-popover" alt="环境的弹出面板：外观设为深色，文字大小的滑块，布局方向和尺寸类别，每项都带着当前的值。" />

弹出面板只显示 App 能改写的项。App 里的 Server 早于 1.2 时，没有“环境”按钮。

## 修改之后 {#what-happens-after-a-change}

Cutaway 等半秒，让 App 重新绘制，然后重新载入整棵树和每一张截图，保留你的选中、展开、聚焦和相机。文字大小在你松开滑块时才发送；拖动时，它的名字随之变化。

有的 App 换外观要更久。如果预览里仍是旧的外观，选择**显示 › 刷新**（<kbd>⌘R</kbd>）。

如果 App 做不到某项修改，弹出面板会说明原因，例如“App 不能这样改写，什么都没有改。”，这项设置随之复原。

## 改写与连接 {#overrides-and-the-connection}

- 连接关闭时，App 里的 Server 撤销改写，所以你停止检查之后，App 不会留着它们。
- Cutaway 重新连接之后，设置显示的是 App 当时的值；Cutaway 不会自己再次应用你的改写。
- 带着改写存储的存档会保留它们：存档窗口的工具栏写出它们，例如“深色 · AX3”。见[存档与导出](/zh-Hans/guide/archives)。

## 下一步 {#next}

<NextSteps :items="[
  { title: '属性', text: '比较一种颜色在浅色和深色下的值。', link: '/zh-Hans/guide/attributes' },
  { title: '存档与导出', text: '保留深色模式下的检查。', link: '/zh-Hans/guide/archives' }
]" />
