---
description: Cutaway 与 CutawayServer 在 1.2 之后计划的方向。
---

# 路线图 {#roadmap}

以下是 1.2 之后计划的方向，Cutaway 与 CutawayServer 共用。顺序和范围可能会变。

- **交互分析。** 显示手势识别器和 target–action 对；启用和停用手势；调用对象的方法。
- **大型层级。** 只截取可见图层的快速模式；分块传输非常大的图像。
- **更多连接方式和平台。** 经过认证和加密的 Wi-Fi 连接；tvOS 和 visionOS。
- **SwiftUI。** 在图层树旁边显示 SwiftUI 视图的语义层级。

需要新消息或新字段的功能，同样要改[协议](/zh-Hans/protocol/)。协议只以追加的方式增长，所以旧的 App 能继续与新的版本一起使用（见[版本与兼容](/zh-Hans/protocol/versions)）。

## 1.2 已完成 {#done-in-1-2}

1.0 之后计划的宿主 App 扩展接口已在 1.2 推出：[自定义属性、虚拟节点、默认折叠的视图、颜色名和排除截图的视图](/zh-Hans/integrate/customizing)。改写 App 的环境和关联你的源代码也在 1.2 推出；见[版本记录](/zh-Hans/resources/releases)。

## 提出需求 {#ask-for-something}

在所属仓库里用 issue 模板建议功能或报告缺陷：

- [Cutaway](https://github.com/nothingsh/Cutaway/issues)，Mac App；
- [CutawayServer](https://github.com/nothingsh/CutawayServer/issues)，iOS SDK；
- [Cutaway Protocol](https://github.com/nothingsh/CutawayProtocol/issues)，新的消息或字段。

每个版本是一个 GitHub 里程碑：在某个里程碑里的 issue 计划在那个版本做，没有里程碑的还没有排期。
