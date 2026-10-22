---
description: Cutaway 每个版本的变化，以及下载的链接。
---

# 版本记录 {#release-notes}

每个版本都在 [GitHub Releases](https://github.com/nothingsh/Cutaway/releases) 上，附有磁盘映像、zip 和它们的 SHA-256 校验和。哪个 Cutaway 能与哪个 CutawayServer 搭配，见[版本与兼容](/zh-Hans/protocol/versions)。

## 1.2.0 <Badge type="tip" text="当前" /> {#_1-2-0}

Cutaway 1.2.0 使用协议 1.2。它能与集成了 CutawayServer 1.0 或 1.1 的 App 一起使用；下面标出的功能需要 [CutawayServer 1.2.0](https://github.com/nothingsh/CutawayServer/releases/tag/1.2.0)。

[GitHub 上的 Cutaway 1.2.0](https://github.com/nothingsh/Cutaway/releases/tag/v1.2.0)

**环境**（需要 CutawayServer 1.2）

- 从工具栏的**环境**按钮或**显示 › 环境**改写 App 的外观、文字大小（XS 到 AX5）、布局方向和尺寸类别。<kbd>⇧⌘A</kbd> 在浅色与深色之间切换。
- 修改之后，Cutaway 等 App 重新绘制，然后刷新整棵树。**复原**把 App 自己的环境还给它，关闭检查也一样。
- 存档记住改写，并在窗口标题下面写出它们。

**你的源代码**

- 用**文件 › 关联项目文件夹…**，把一个 App 与它的 Xcode 项目连起来；**设置 › 项目**列出这些文件夹。Cutaway 只读取它们。
- **在 Xcode 中打开**（<kbd>⌥⌘O</kbd>）从 App 自己的类跳到它们的声明，Swift 和 Objective-C 都可以。
- 颜色以与之相符的资源目录颜色集命名，文字显示它来自的 String Catalog 键。
- **编辑 › 拷贝 LLDB 命令**拷贝一条命令，打印所选的对象，或在它的 frame 改变时停下。

**属性**

- 动态颜色把浅色和深色的值并排显示。
- 新的“辅助功能”一节；文字样式、画出的和截断的行数、图片、index path 和项目数各占一行。
- 指向其他视图的值（例如 stack view 的 arranged subviews）显示为小块，可以指向和点按。

**你的 App 自己的信息**（需要 CutawayServer 1.2）

- 新的 App 一节，列出你的 App 加入的属性分组，可以像其他属性一样编辑。
- 你的 App 登记的颜色以名字显示。
- 你的 App 标出的视图在列表里默认折叠；它排除的视图画上斜线，不截图。
- 虚拟节点：视图自己画出的界面部分，例如图表的柱子，以自己的图标和虚线边框出现在树里。

**另外**

- 在图层列表的一行上按住 <kbd>⌥</kbd>，测量到那个图层的距离。
- 带一千个属性的图层，属性立刻就显示出来；截图到得更快：5,000 个图层约 1.4 秒，原来是 3.8 秒。

## 1.1.0 {#_1-1-0}

[GitHub 上的 Cutaway 1.1.0](https://github.com/nothingsh/Cutaway/releases/tag/v1.1.0) · [CutawayServer 1.1.0](https://github.com/nothingsh/CutawayServer/releases/tag/1.1.0)

Cutaway 1.1.0 使用协议 1.1。它能与集成了 CutawayServer 1.0 的 App 一起使用，接 CutawayServer 1.1.0 时显示下面的全部内容。

- **属性**按用途排成一个列表，分五节：内容、外观、布局、行为和对象。相关的属性合在一行；值带着单位，以复选框、分段控件显示，边距画成方框，颜色带着系统名字。没有效果的值变淡，原因写在提示里。
- 超出 App 报告的限制的值不会发送：输入框保持打开，并说明原因。
- 属性的过滤、停留在视野里的分节标题，以及一行图层的上级图层。
- 约束的另一端是一个小块。指向一条约束，就在预览里标出它的另一端；或者打开**显示约束的另一端**（<kbd>⇧⌘K</kbd>）。
- **层级**：每个图层有表示其种类的图标，App 自己的类是实心的；参考线显示嵌套；顶行的上级图层吸顶显示；**选择父图层**（<kbd>⌘↑</kbd>）和**选择第一个子图层**（<kbd>⌘↓</kbd>）。
- **预览**：所选图层旁边有一个标签；边框可以关闭、单色或按类别，也可以只给 App 自己的类画。
- App 列表把模拟器和 USB 设备分组，可以用方向键和 Return 操作。
- 外观的设置：系统、浅色或深色。

## 1.0.0 {#_1-0-0}

[GitHub 上的 Cutaway 1.0.0](https://github.com/nothingsh/Cutaway/releases/tag/v1.0.0) · [CutawayServer 1.0.0](https://github.com/nothingsh/CutawayServer/releases/tag/1.0.0)

第一个公开版本，使用协议 1.0。

- 每个窗口的图层树，标出视图控制器的根视图，以及持有各个图层的成员变量。
- 每个图层的截图，平铺为 2D 或在 3D 中分开，每个位置、大小、旋转和缩放都与设备上相同，包括 3D 变换。
- 用 <kbd>⌥</kbd> 在两个图层之间测距，2D 和 3D 下都可以。
- 可编辑的属性，立即作用于运行中的 App，<kbd>⌘Z</kbd> 撤销。
- 指向一个视图的 Auto Layout 约束，标出未生效的。
- 搜索、聚焦于一棵子树、展开到某一层、单独刷新一棵子树。
- 在任何一台 Mac 上无需设备即可打开的 `.cutaway` 存档，以及把图层截图导出为 PNG。
- 自己找到模拟器里和 USB 设备上的 App，App 回来时重新连接，并跟随 App 进入后台、回到前台。
- 提供英文、简体中文、繁体中文、日文和韩文。
- **检查更新…** 向 GitHub 查询有没有更新的版本。
