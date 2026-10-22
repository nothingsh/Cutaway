---
description: 关联你的项目文件夹，在 Xcode 中打开类，看到颜色和文字的名字；为所选图层拷贝 LLDB 命令。
---

# 源代码 {#source-code}

从你在 Cutaway 里看到的走到你的代码：在 Xcode 中打开一个类，看出一个值来自哪个颜色集或文案的键，在调试器里拿到同一个对象。

<div class="facts">
  <Badge type="info" text="Cutaway 1.2" />
</div>

在 Xcode 中打开、给颜色和文字写出名字，都要先关联项目文件夹。拷贝 LLDB 命令不需要。

## 关联项目文件夹 {#link-a-project-folder}

1. 检查你的 App，或打开它的一份存档。
2. 选择**文件 › 关联项目文件夹…**，选中你的 Xcode 项目所在的文件夹。

Cutaway 按 App 的 bundle ID 记住这个文件夹，实时检查和这个 App 的存档都用它。在**设置 › 项目**里更换或移除它（见[设置](/zh-Hans/guide/settings)）。

Cutaway 只读取这个文件夹：Swift 和 Objective-C 源文件、资源目录和 String Catalog。它从不往里写，也不把它发到任何地方。它在后台读取，跳过隐藏的文件夹、构建产物和第三方代码（`DerivedData`、`build`、`.build`、`SourcePackages`、`Pods`、`Carthage`、`node_modules`），以及 `.framework`、`.xcframework` 和 `.bundle` 文件夹；大于 4 MB 的源文件和大于 64 MB 的字符串表也会跳过，读到 20 万个文件为止。打开检查器或用 <kbd>⌘R</kbd> 刷新时，它重新读取改过的文件。

如果文件夹被移走了，或者它所在的磁盘没有连接，Cutaway 会去找它；找不到时，在第一次用到它时询问：**重新选择…**、**以后再说**。

## 在 Xcode 中打开一个类 {#open-a-class-in-xcode}

当你的项目声明了所选图层、它的视图或它的视图控制器的类时：

- 点按属性的“对象”一节里类名旁边的**在 Xcode 中打开**按钮，或者
- 选择**文件 › 在 Xcode 中打开**（<kbd>⌥⌘O</kbd>），或那一行、那个图层的右键菜单里的**在 Xcode 中打开**。

Xcode 打开那个文件，停在声明处。这个类在几处声明时，从文件和行号的列表里选一处。能找到的有 Swift 的类、结构体、枚举和 actor，以及 Objective-C 的 `@interface` 和 `@implementation`；扩展和类别不算声明。

系统类没有“在 Xcode 中打开”。没有安装 Xcode 时，文件用它的默认 App 打开。

<Shot name="guide-source-open" alt="“对象”一节里，App 的类旁边有“在 Xcode 中打开”按钮；以及“文件”菜单里的“在 Xcode 中打开”一项。" />

## 看出颜色从哪里来 {#see-where-a-color-comes-from}

关联了文件夹之后，与资源目录里某个颜色集相符的颜色以颜色集的名字显示，提示里写着是哪种外观相符，例如“资源：BrandBlue（深色）”。动态颜色只有浅色和深色的值都相符时才算相符。名字怎样选出，见[属性](/zh-Hans/guide/attributes#read-a-color)。

## 看出文字来自哪个键 {#see-which-key-a-text-comes-from}

关联了文件夹之后，与 String Catalog 或 `.strings` 文件里某个值相符的文字（任何语言都可以），下面会写出它的键和表名，例如“键 home.title · Localizable”。由 `%@ items` 这样的格式生成的文字也能对上。有几个键相符时，显示第一个，提示里列出其余的。

## 拷贝 LLDB 命令 {#copy-an-lldb-command}

要在调试器里拿到所选的对象，选择**编辑 › 拷贝 LLDB 命令**，或那一行、那个图层的右键菜单里的**拷贝 LLDB 命令**：

- **打印对象**拷贝一条打印这个视图的命令，没有视图时打印图层：

  ```text
  expr -l objc -O -- (id)0x10a2b3c40
  ```

- **frame 改变时停下**拷贝两个断点，在图层的 position 或 bounds 被设置时停下：

  ```text
  breakpoint set -n "-[CALayer setPosition:]" -c '(void *)$arg1 == (void *)0x600001234560'
  breakpoint set -n "-[CALayer setBounds:]" -c '(void *)$arg1 == (void *)0x600001234560'
  ```

App 暂停时，把它们贴进 Xcode 的调试控制台。上面的地址只是例子；Cutaway 用的是所选对象的地址。

这些命令要用到对象的地址，集成了 CutawayServer 1.1 或更新版本的 App 会发送它。在存档里它们仍然可用，并注明地址是存档时的：它们只在 App 的同一次运行里有效。

## 下一步 {#next}

<NextSteps :items="[
  { title: '属性', text: '查看并编辑所选的图层。', link: '/zh-Hans/guide/attributes' },
  { title: '设置', text: '更换或移除关联的文件夹。', link: '/zh-Hans/guide/settings' }
]" />
