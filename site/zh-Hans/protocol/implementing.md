---
description: 为 Cutaway Protocol 编写你自己的客户端或服务端，并用参考夹具测试它。
---

# 实现一端 {#implementing-a-peer}

你可以为这个协议另写一个客户端或服务端：一个导出 App 层级的命令行工具，一个面向其他 UI 框架的服务端，或一套测试工具。所需的一切都在 [CutawayProtocol](https://github.com/nothingsh/CutawayProtocol) 仓库里，它本身不含 Swift 代码。

| 路径 | 是什么 |
|---|---|
| `PROTOCOL.md` | 规范性的[规范](/zh-Hans/protocol/spec)。带编号的条款（`P-TRANS-01`、`P-FRAME-03`……）是要求；其余都是解释 |
| `schema/cutaway.fbs` | FlatBuffers schema。每一帧的载荷都是这里定义的 `Frame` |
| `schema/released/` | 每个已发布的 `MAJOR.MINOR` 的 schema 快照，发布后不再修改 |
| `fixtures/` | 用来测试实现的参考帧：JSON 源文件、编译出的缓冲区，以及线上的确切字节 |
| `PROTOCOL_VERSION` | 当前的协议版本 |
| `FLATBUFFERS_VERSION`、`FLATC_SHA256` | 钉住的 `flatc` 版本，以及它的 macOS 二进制文件的校验和 |

<div class="steps">

## 阅读规范 {#read-the-specification}

从头到尾读一遍 `PROTOCOL.md`。条款都很短，彼此互相引用；[概览](/zh-Hans/protocol/)是它们的地图。

## 从 schema 生成代码 {#generate-code-from-the-schema}

用钉住的 `flatc`（见 `FLATBUFFERS_VERSION`）从 `schema/cutaway.fbs` 生成代码。`scripts/get-flatc.sh` 把这个确切的版本下载到 `.tools/` 并检查校验和。把仓库的一个 tag 钉住，例如作为 git submodule，这样你所依据的 schema 不会在你脚下变动。

## 用夹具测试 {#test-against-the-fixtures}

`fixtures/bin/` 里的每个场景有两种文件：

- **`.bin`** 是一个缓冲区，不带长度前缀：用来测试你能解码一帧。
- **`.stream`** 是整个场景的一个方向，每一帧前面都有它的 4 字节长度：正是 TCP 连接上的字节，用来测试你能从字节流里切出帧。

这些场景涵盖握手与版本不匹配、忙碌的服务端、图标、层级（含虚拟节点和一棵不截图的子树）、图层详情（正常、边界情况、取消、失败）、App 变为不活跃、编辑属性（接受与拒绝）、子树，以及环境。`fixtures/README.md` 列出了每个场景及它验证的条款。

## 提高校验器的表数上限 {#raise-your-verifier-s-table-limit}

如果你的 FlatBuffers 运行库的校验器对表的数量有上限，把它调高。协议允许的帧所含的表远多于大多数默认值：对于大小在上限之内、合乎规范的帧，接收方不得因为它的表数、嵌套深度或表面上的大小而拒绝它（P-FRAME-06）。

</div>

## 容易出错的地方 {#easy-to-get-wrong}

- **长度前缀不是 FlatBuffers 的。** 一帧是 4 字节小端序的长度 `N`，然后是一个*普通的* FlatBuffer。不要用 FlatBuffers 带长度前缀的函数；`.stream` 夹具给出了确切的字节（P-FRAME-01）。
- **先校验再读取。** 在读取任何字段之前校验整个缓冲区；帧校验失败、过长（超过 256 MiB）或标识不对时关闭连接（P-FRAME-03、04）。
- **默认值不写出。** `flatc` 不写出等于默认值的字段，所以读回来是 0、false 或枚举的第一个成员。写测试的预期时要考虑到这一点。
- **服务端总会回答 `Hello`。** 即使主版本不同，服务端也会在关闭之前发出自己的 `Hello`，好让客户端告诉用户原因。握手完成之前，客户端收到的任何其他帧都意味着握手失败（P-HELLO-02、03、07）。
- **按较低的次版本工作。** 绝不发送协商出的次版本里没有的消息、枚举值或联合成员；新的表字段可以发（P-HELLO-04）。
- **客户端发出的每一帧都占用自己的 `request_id`**，包括 `Cancel`，从 1 开始递增。按 `request_id` 匹配回答，不要只靠顺序（P-REQ-01）。
- **`Cancel` 可能来得太晚。** 流可能在服务端读到你的 `Cancel` 之前就正常结束；这时 `Cancel` 被忽略。让未答的请求少于 64 个，服务端就永远不会暂停读取，`Cancel` 也能及时生效（P-REQ-04、09）。
- **按错误代码分支，从不按消息分支。** `Error.message` 是给人看的英文；代码列在规范的 [Error codes](/zh-Hans/protocol/spec#error-codes) 一节。
- **服务端等待 `Hello` 5 秒**，之后关闭连接（P-HELLO-06）。

## 检查协议仓库本身 {#check-the-protocol-repository-itself}

仓库的 `scripts/verify.sh` 下载钉住的 `flatc`，编译 schema，重建每个夹具并与 `fixtures/bin/` 比较，按 schema 表达不了的条款检查夹具，并检查 schema 相对最新发布的快照是允许的演进。它需要 `bash`、`curl` 和 `python3`，只在 macOS 上运行。

## 接下来 {#next}

<NextSteps :items="[
  { title: '规范', text: '规范性的原文，逐条列出。', link: '/zh-Hans/protocol/spec' },
  { title: '版本与兼容', text: '协议怎样演进。', link: '/zh-Hans/protocol/versions' },
  { title: '参与贡献', text: '提出对协议的修改。', link: '/zh-Hans/resources/contributing' }
]" />
