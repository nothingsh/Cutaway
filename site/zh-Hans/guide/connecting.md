---
description: Cutaway 怎样找到你的 App、App 列表显示什么，以及 App 进入后台或连接断开时会怎样。
---

# 连接 App {#connecting-to-apps}

Cutaway 会自己找到集成了 CutawayServer 的 App。这一页说明 App 列表，以及 App 来来去去时 Cutaway 怎样做。

## 选择一个 App {#choose-an-app}

Cutaway 启动时打开 App 列表；也可以用**窗口 › 显示 App 列表**（<kbd>⇧⌘0</kbd>）或点按检查窗口工具栏里的 App 名打开它。App 按运行的位置分组：模拟器在**这台 Mac** 下面，经 USB 连接的每台设备在它自己的名字下面。

点按一个 App，或用方向键选中它再按 <kbd>Return</kbd>。它的检查窗口随即打开，先显示图层树，再陆续填上截图。

<Shot name="guide-applist" alt="App 列表里有一个在模拟器中运行的 App，可以选中。" />

列表是空的时，它写着**还没有可检查的 App**，并链接到[如何集成 CutawayServer](/zh-Hans/integrate/)。

## Cutaway 在哪里找 {#where-cutaway-looks}

- **模拟器。** Cutaway 每两秒尝试一次 `127.0.0.1` 上的 48160 至 48167 端口，这台 Mac 上模拟器里的 CutawayServer 在这些端口监听。
- **设备。** 它经系统的 `usbmuxd` 在经 USB 连接的每台 iPhone 和 iPad 上尝试同样的端口。设备必须已解锁，并且信任这台 Mac。

回答了握手的 App 会被列出。只要 App 还在列表里，Cutaway 就为它保持一个连接；已经有别的客户端连着的 App，Cutaway 不去打扰：服务端一次只服务一个客户端。

## 读懂 App 的标记 {#read-an-app-s-badge}

| 标记 | 含义 |
|---|---|
| **在后台** | App 在后台。它回到前台后会载入图层。 |
| **未激活** | App 在前台但不活跃，例如被控制中心或系统提醒挡住时。 |
| **不兼容** | App 的服务端使用的协议版本，这个 Cutaway 不支持。这一行写着两边的版本；更新旧的那一方。见[版本与兼容](/zh-Hans/protocol/versions)。 |

## App 进入后台时 {#when-the-app-goes-to-the-background}

Cutaway 在预览上方说明这一点（“… 未处于活跃状态。它回到前台后会继续载入。”）并等待。你打开的东西都不会丢；App 回来后继续载入。

## 连接断开时 {#when-the-connection-is-lost}

窗口保留最后的画面，并写着**与 *YourApp* 的连接已断开。正在等待它恢复…**。再次找到同一个 App 时，例如你从 Xcode 再次运行它之后，Cutaway 在同一个窗口里重新连接、重新载入图层树，保持你的视图不变。

10 秒没有得到回答的请求会被放弃。如果 App 发来协议禁止的内容，Cutaway 会关闭连接。

::: tip 留下你的发现
想在没有设备时查看一次检查，就在断开之前把它存为存档。见[存档与导出](/zh-Hans/guide/archives)。
:::

## 下一步 {#next}

<NextSteps :items="[
  { title: '图层列表', text: '读懂一行，过滤，聚焦于一棵子树。', link: '/zh-Hans/guide/hierarchy' },
  { title: '常见问题与故障排除', text: 'App 没有出现在列表里时。', link: '/zh-Hans/resources/faq' }
]" />
