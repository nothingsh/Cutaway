---
description: 你的 App 的哪些构建里有 CutawayServer，以及怎样在 Debug 之外的配置里使用它。
---

# Debug 与 Release 构建 {#debug-and-release-builds}

默认情况下，CutawayServer 只编译进定义了 `DEBUG` 的构建。在其他构建里，`start()` 是一个空函数，产物里没有监听的代码。

<BuildsDiagram />

## 哪些配置定义了 `DEBUG` {#which-configurations-define-debug}

包里能否看到 `DEBUG`，取决于宿主 App 构建配置的**名字**，而不是它的设置：

| 宿主的配置名 | 包里定义了 `DEBUG` 吗？ |
|---|---|
| `Debug`，以及含 `Debug` 或 `Development` 的名字（例如 `DebugQA`） | 是 |
| `Release`、`Staging`、`QA` 和其他任何名字，即使这个配置是从 Debug 复制来的 | 否 |

所以，一个从 `Debug` 复制来、名为 `Staging` 的配置，构建出的 CutawayServer 仍是空函数，App 永远不会出现在 Cutaway 的列表里。

## 在其他配置里使用服务端 {#use-the-server-in-other-configurations}

要在第二类配置里使用服务端，打开包的 trait `ReleaseEnabled`。

::: code-group

```swift [Package.swift]
.package(
    url: "https://github.com/nothingsh/CutawayServer",
    from: "1.2.0",
    traits: ["ReleaseEnabled"]
)
```

```text [Xcode 工程]
在 CutawayServer 这个包依赖上打开 trait ReleaseEnabled。
```

```text [XcodeGen]
把这个 trait 列在 packages.<name>.traits 下。
CutawayServer 仓库里的 Demo/release-enabled.yml 是一个例子。
```

:::

::: danger 这个 trait 作用于所有配置
打开 `ReleaseEnabled` 之后，服务端会编译进宿主的**每一个**配置，包括你提交到 App Store 的那个。这时要由你的 App 自己在发布的构建里不调用 `start()`，例如只在你自己的某个条件下调用它。
:::

## 没有服务端的构建里有什么 {#what-a-build-without-the-server-contains}

既没有 `DEBUG` 也没有这个 trait 时，产物里除了入口之外没有这个包的任何东西：没有服务端，没有 `Network` 的符号，也没有协议的编码代码。CutawayServer 自己的测试脚本用 `nm` 在它的演示 App 的 Release 构建上检查这一点。

[扩展接口](/zh-Hans/integrate/customizing)（`describe`、`registerColor`）同样编译进每一个配置，所以你的 App 不用加自己的条件就能调用它；没有服务端时，登记什么也不做。

`CutawayWire` 和 `CutawayFlatBuffers` 是这个包的另外两个模块，属于实现细节。宿主可以在 Debug 构建里导入它们，但其中没有任何东西是公开 API，也不受版本号约束。

## 接下来 {#next}

<NextSteps :items="[
  { title: '定制 Cutaway 显示的内容', text: '你自己的属性、虚拟节点和颜色名。', link: '/zh-Hans/integrate/customizing' },
  { title: '在设备上的行为', text: '服务端在哪里监听，截取时会动到什么。', link: '/zh-Hans/integrate/on-device' }
]" />
