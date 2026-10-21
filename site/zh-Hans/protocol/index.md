---
description: 用一页说明 Cutaway 与 CutawayServer 怎样通信。
---

# Cutaway Protocol {#the-cutaway-protocol}

Cutaway 与 CutawayServer 不共享代码。两者经一个小的、带版本的线上协议通信，它定义在自己的仓库 [CutawayProtocol](https://github.com/nothingsh/CutawayProtocol) 里：一份 [FlatBuffers](https://flatbuffers.dev) schema，一份条款带编号的规范性[规范](/zh-Hans/protocol/spec)，以及用来测试任何一端的夹具。两边都把这个仓库的一个 tag 钉为 git submodule，并从 schema 生成各自的代码。

本页只是导览。下面的每一条规则都是规范里的一个条款（`P-TRANS-01`、`P-FRAME-03`……），要紧的地方附了链接。

<div class="facts">
  <Badge type="info" text="协议 1.2" />
  <Badge type="info" text="FlatBuffers" />
  <Badge type="info" text="MIT 许可证" />
</div>

<PartsDiagram />

## 传输 {#transport}

- 服务端在 TCP 上监听，**只用回环地址**，依次尝试端口 48160 至 48167，绑定第一个可用的（P-TRANS-01、02）。
- 模拟器与 Mac 共用回环地址。经 USB 连接的设备经由 macOS 的 `usbmuxd` 到达，服务端对它一无所知。
- 同一时间只服务一个客户端：已有连接时，新的连接会收到 `Error`（代码 `Busy`）并被关闭（P-TRANS-03）。

回环之外的传输方式（例如 Wi-Fi）留给以后的版本，届时连接必须经过认证并加密。

## 帧 {#frames}

<FrameDiagram />

一帧是 4 字节小端序的长度 `N`，后面跟着 `N` 字节，存放一个普通的 FlatBuffer，根类型为 `Frame`，文件标识为 `CTWY`（P-FRAME-01、02）。这**不是** FlatBuffers 带长度前缀的格式；`.stream` 夹具给出了确切的字节。

`N` 不得超过 256 MiB，接收方在读取任何字段之前先校验整个缓冲区（P-FRAME-03、04）。校验不通过的帧会让连接被关闭。

## 握手与版本 {#handshake-and-versions}

客户端的第一帧是 `Hello`；服务端总是以自己的 `Hello` 回答，带上它的协议版本和 App 的信息（P-HELLO-01、02）。

- **主版本不同：** 握手失败，两边都关闭连接（P-HELLO-03）。因为服务端仍然发出了它的 `Hello`，Cutaway 可以显示双方各是什么版本，以及为什么这个 App 不能检查。
- **次版本不同：** 握手成功，两边都按较低的次版本工作（P-HELLO-04）。

[版本与兼容](/zh-Hans/protocol/versions)一页写了这些规则，以及哪些版本可以搭配使用。

## 请求、流与事件 {#requests-streams-and-events}

<ExchangeDiagram />

- **`request_id`。** 客户端从 1 开始给请求编号，在一个连接内递增；每个回答都带着所属请求的编号。0 留给握手、事件，以及不回答某个具体请求的错误（P-REQ-01）。
- **普通请求**恰好得到一个回答：`GetAppIcon`、`GetHierarchy`、`GetSubtree`、`SetAttribute`，以及 1.2 起的 `GetEnvironment` 和 `SetEnvironment`（P-REQ-02）。
- **流式请求。** `GetLayerDetails` 按图层 ID 请求图像、属性和约束。它的回答是零个或多个 `LayerDetailsChunk` 帧，然后恰好一个 `StreamEnd`（P-REQ-03）。
- **取消。** `Cancel` 提前结束一个流；流以 `StreamEnd`（状态 `Cancelled`）结束。它本身没有回答（P-REQ-04）。
- **顺序。** 服务端按收到的顺序一次处理一个请求，`Cancel` 除外：它在当前请求进行中就会被处理（P-REQ-06）。
- **背压。** 有 64 个请求未答时，服务端可以暂停读取；这时 TCP 的流量控制让客户端等待。协议本身没有流量控制（P-REQ-09）。
- **事件。** 握手之后，以及 App 的活跃状态每次改变时，服务端都以 `request_id` 0 发送 `AppStateChanged`（P-EVT-01、02）。App 不活跃时，需要截取或修改它的请求以 `AppNotActive` 失败（P-APP-01）。

## 错误 {#errors}

`Error` 带一个稳定的 `ErrorCode` 和一段给人看的英文消息。客户端按代码分支，从不按文字分支。

| 代码 | 含义 |
|---|---|
| `Unknown` | 未分类的错误 |
| `MalformedFrame` | 帧的长度、文件标识或校验不合法 |
| `UnexpectedMessage` | 当前状态下不应出现的消息 |
| `Busy` | 服务端已经在服务另一个客户端 |
| `AppNotActive` | App 不活跃，无法截取 |
| `Internal` | 服务端内部错误 |
| `LayerNotFound` | 请求指名的图层不存在 |
| `AttributeNotEditable` | 属性不存在或不能修改 |
| `InvalidAttributeValue` | 要写入的值不合法，或超出属性的范围 |
| `NotSupported` | 服务端无法应用请求要求的改写（1.2） |

## 消息的内容 {#what-the-messages-carry}

| 消息 | 用途 |
|---|---|
| `GetAppIcon` → `AppIcon` | App 的图标，用于 App 列表 |
| `GetHierarchy` → `Hierarchy` | 整棵图层树，不含图像和属性 |
| `GetSubtree` → `Hierarchy` | 一个图层及其全部后代，用于刷新树的一部分 |
| `GetLayerDetails` → `LayerDetailsChunk`…、`StreamEnd` | 所请求图层的图像、属性和约束 |
| `SetAttribute` → `SetAttributeResult` | 修改一个图层的一项属性；结果里是修改之后这个图层的属性 |
| `GetEnvironment`、`SetEnvironment` → `Environment` | App 的特征环境，以及 Cutaway 对它的改写（1.2） |
| `AppStateChanged` | 事件：App 变为活跃或不活跃 |

## 继续阅读 {#go-further}

<NextSteps :items="[
  { title: '版本与兼容', text: '协议怎样演进，哪些版本可以搭配使用。', link: '/zh-Hans/protocol/versions' },
  { title: '实现一端', text: '生成代码，用夹具测试。', link: '/zh-Hans/protocol/implementing' },
  { title: '规范', text: '规范性的原文，逐条列出。', link: '/zh-Hans/protocol/spec' }
]" />
