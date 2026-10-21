---
description: Cutaway Protocol 怎样定版本，以及哪些版本的 Cutaway 与 CutawayServer 可以搭配使用。
---

# 版本与兼容 {#versions-and-compatibility}

协议的版本是 `MAJOR.MINOR`；协议仓库的发布以 `vMAJOR.MINOR.PATCH` 打 tag。Cutaway 和 CutawayServer 各自使用一个协议版本，由握手决定两者一起用哪个。

## 哪些版本可以搭配使用 {#which-releases-work-together}

| Cutaway | CutawayServer | 协议 |
|---|---|---|
| 1.0.0 | 1.0.0 | 1.0 |
| 1.1.0 | 1.1.0 | 1.1 |
| 1.2.0 | 1.2.0 | 1.2 |

**任何 1.x 的 Cutaway 都能与任何 1.x 的 CutawayServer 搭配使用。** 次版本不同时，两边按较低的那个工作：Cutaway 1.2 与 CutawayServer 1.1 使用协议 1.1，Cutaway 1.1 与 CutawayServer 1.2 也是如此。你得到的是较旧的一边所知道的功能。

0.x 与 1.x 的版本不能搭配使用：1.0 是一个主版本，握手按设计会失败。

## 两边都要 1.2 的功能 {#what-needs-1-2-on-both-sides}

这些功能随协议 1.2 加入，只有 Cutaway 和 CutawayServer 都是 1.2 或更新版本时才会出现：

| 功能 | 出现在哪里 |
|---|---|
| 改写 App 的环境：外观、文字大小、布局方向、尺寸类别 | 工具栏的“环境”按钮，**显示 › 环境** |
| 虚拟节点、默认折叠的视图、不截图的视图 | 图层列表和预览；见[定制](/zh-Hans/integrate/customizing) |
| App 加的属性分组 | 检查器的 App 一节 |
| App 起名的颜色；动态颜色的浅色值与深色值 | 检查器里颜色的行 |
| “辅助功能”一节 | 检查器 |
| 指向其他图层的属性，例如 stack view 的 `arrangedSubviews` | 可以指向、点按的小块 |

若一边较旧，Cutaway 的其余功能照旧；只是没有这些。

## 版本不匹配时 {#when-versions-don-t-match}

主版本不同时，Cutaway 仍会列出这个 App，写出两边的版本，并说明它不能检查。更新较旧的一边：Cutaway 从它的 [Releases](https://github.com/nothingsh/Cutaway/releases) 或 **Cutaway › 检查更新…** 更新，CutawayServer 则在你的包依赖里提高版本。

## 协议怎样演进 {#how-the-protocol-evolves}

- **只追加。** schema 只以追加的方式增长：字段加在表的末尾，成员加在枚举和联合的末尾。结构体、文件标识和根类型永不改变。其他任何改动都是新的主版本（P-EVO-01 至 03）。
- **缺省即照旧。** 较早版本的发送方不写的字段，其含义必须是加入它之前的行为（P-EVO-06）。
- **次版本经过协商。** 任何一边都不发送协商出的次版本里不存在的消息、枚举值或联合成员。新的表字段可以照发，因为接收方会忽略它不认识的字段（P-HELLO-04、P-EVO-07）。
- **修订版本**只改措辞或夹具，不动 schema。
- **自 1.0 起冻结。** 协议自 1.0 起冻结：此后只在次版本里增长。帧格式和最初的十个消息（`Hello` 至 `Error`）在任何主版本里都不变，所以任何两个版本总能读懂对方的握手（P-EVO-05）。

完整的规则是[规范](/zh-Hans/protocol/spec#evolution)里的 `P-EVO` 条款。

## 存档 {#archives}

`.cutaway` 存档记下了存档时协商出的协议版本。存档不经过协商，所以 Cutaway 不打开以比自己更新的次版本写下的存档：它会说明存档较新，而不是读错。较旧的存档照常打开。

## 接下来 {#next}

<NextSteps :items="[
  { title: '实现一端', text: '生成代码，用夹具测试。', link: '/zh-Hans/protocol/implementing' },
  { title: '版本记录', text: 'Cutaway 每个版本加了什么。', link: '/zh-Hans/resources/releases' }
]" />
