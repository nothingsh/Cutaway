---
description: 把你的 App 自己的属性、虚拟节点、颜色名和截取设置加进 Cutaway 显示的内容。
---

# 定制 Cutaway 显示的内容 {#customizing-what-cutaway-shows}

Cutaway 自己读取 UIKit 和 Core Animation。你的 App 知道得更多：自定义视图里装着什么，它自己画的图表由哪些部分组成，品牌颜色叫什么名字，哪些视图里是敏感内容。CutawayServer 的扩展接口让你把这些告诉 Cutaway。

<div class="facts">
  <Badge type="info" text="需要 CutawayServer 1.2" />
  <Badge type="info" text="需要 Cutaway 1.2" />
</div>

| 你登记的 | Cutaway 显示的 |
|---|---|
| 一个类的[属性分组](#add-attributes) | 检查器里的 **App** 一节，每个分组一个小标题；提供了 `set` 闭包的可以编辑 |
| [虚拟节点](#show-what-a-view-draws-itself) | 图层列表里带自己图标的行、预览里的虚线框，可以选中、检查 |
| [默认折叠](#collapse-and-exclude) | 一次检查开始时，这个视图的行是折叠的 |
| [不截取](#collapse-and-exclude) | 这个视图在预览里画斜线，不出现在任何图像里 |
| [颜色名](#name-your-colors) | 凡是属性的颜色与之相同，都显示你起的名字 |

::: tip 可以放心发布
扩展接口编译进每一个配置，所以你不用加自己的条件就能调用它。在没有服务端的构建里（见 [Debug 与 Release 构建](/zh-Hans/integrate/builds)），登记什么也不做。
:::

## 描述一个类 {#describe-a-class}

一切从 `CutawayServer.describe(_:_:)` 开始，针对一个 `UIView` 类或一个 `CALayer` 类。描述作用于这个类**及其子类**的实例：

```swift
import CutawayServer

@MainActor
func registerWithCutaway() {
    CutawayServer.describe(SalesChartView.self, CutawayServer.Description(
        attributes: { chart in [/* attribute groups, below */] },
        virtualChildren: { chart in [/* virtual nodes, below */] },
        isCollapsedByDefault: false,
        isExcludedFromCapture: false
    ))
}
```

`Description` 的每个字段都是可选的：

| 字段 | 作用 |
|---|---|
| `attributes` | 实例的属性分组，显示在 Cutaway 自己的属性之后 |
| `virtualChildren` | 实例自己画的界面部分，作为它的图层的子节点显示，排在它的子图层之前 |
| `isCollapsedByDefault` | 实例一开始显示为折叠，例如复杂控件的内部 |
| `isExcludedFromCapture` | 实例和它里面的一切都不出现在任何图像里 |

登记一次即可，例如在启动时紧挨着 `CutawayServer.start()`。描述从 Cutaway 的下一个请求起生效；之后对同一个类再次调用会替换它。

::: warning 闭包只读
`attributes` 和 `virtualChildren` 在主线程上调用，Cutaway 每次读它们给的东西时都会调用：取层级时、读一个节点的属性时，以及修改之后再读一次，好让回答反映这次修改。在一次取详情的请求里，一个图层的虚拟子节点只问一次，不论请求点到它的多少个节点。它们返回的东西在请求答完后丢弃，虚拟节点的标识除外。它们只能读：要改 App，只在属性的 `set` 闭包里改，别处都不行。
:::

几个描述作用于同一个图层时（它的类、它的视图的类，以及它们的父类）：

- 它们的属性分组都显示，图层的在视图的之前，各自从父类往下；
- 虚拟子节点来自带有它们的、最具体的那个描述，视图的优先于图层的；
- 任何一个描述设了 `isCollapsedByDefault` 或 `isExcludedFromCapture`，就生效。

## 加入属性 {#add-attributes}

一个属性分组有一个 ID、一个可选的标题和它的属性。每个属性用对应值的种类的函数来造：

```swift
CutawayServer.Description<SalesChartView>(
    attributes: { chart in
        [
            CutawayServer.AttributeGroup("chart", title: "Chart", [
                .int("barCount", chart.bars.count, section: .content),
                .color("barColor", chart.barColor, section: .appearance, set: { color in
                    chart.barColor = color ?? .systemBlue
                })
            ])
        ]
    }
)
```

Cutaway 把你的 App 加的每个分组都显示在检查器里它自己的 **App** 一节，在"内容"之后，按分组到达的次序，每个分组的标题作为小标题。过滤和折叠与其他各节一样。

<Shot name="integrate-app-section" alt="CutawayDemo 的销售图表的检查器：App 一节里的 Chart 分组，一个可编辑的柱子颜色，显示登记的名字 brandBlue。" />

### 值的种类 {#kinds-of-value}

| 函数 | 值 |
|---|---|
| `.bool` | `Bool` |
| `.int` | `Int` |
| `.double` | `Double` |
| `.string` | `String` |
| `.color` | `UIColor`；动态颜色按它对这个对象解析出的样子显示，并分浅色和深色 |
| `.point`、`.size`、`.rect` | `CGPoint`、`CGSize`、`CGRect` |
| `.insets` | `UIEdgeInsets` |
| `.transform` | `CATransform3D` |
| `.enumeration` | 遵循 `CaseIterable`、原始值为整数的 Swift 枚举，每个 case 按名字显示；不是 Swift 枚举的值，用 `(name, value)` 对的列表 |
| `.references` | 一个属性持有的对象，按次序；其中的视图或视图控制器可以从这里选中。总是只读 |

每个值都可以是 `nil`。

### 选项 {#options}

每个函数先接受属性的名字和值，然后是都有默认值的选项：

| 选项 | 含义 |
|---|---|
| `title` | 检查器里的标签 |
| `section` | 属性属于哪里：`.general`、`.identity`、`.layout`、`.content`、`.appearance`、`.behavior` 或 `.accessibility` |
| `unit` | 用于数字：`.none`、`.points`（以点为单位的长度）或 `.fraction`（1 为整体的比例，显示为百分比） |
| `limits` | 数字可以设成的值：`.atLeast`、`.greaterThan`、`.atMost`、`.lessThan`、`.between` 或 `.free`。只给一个限制时作用于每个分量；否则每个分量给一个，按它的字段的次序 |
| `cluster` | 这个属性可以显示在其中的复合行，以及它在其中的部分：`.font.size`、`.shadow.color`、`.sizing.huggingHorizontal` 等，Cutaway 协议里的每个复合行和部分都有一个常量；`.init(_:slot:)` 接受字符串形式的名字 |
| `inactiveBecauseOf` | 同一对象的另一个属性，写成 `"group.name"`，它现在的值使这个属性不起作用；Cutaway 把它显示为淡色 |
| `acceptsNil` | `set` 能否收到 `nil` |
| `set` | 使属性可以编辑 |

这些选项的类型嵌在 `CutawayServer.Attribute` 里：`CutawayServer.Attribute.Section`、`.Unit`、`.Limit` 和 `.Cluster`。用上面以点开头的写法，就不必写出它们的全名。

Cutaway 1.2 把你的 App 加的每个分组都显示在 App 一节里，按你返回的次序，不论每个属性的 `section` 是什么。`section` 仍随属性一起发送，作为给按用途排序的客户端的提示。

分组的 ID 以 `app.` 加上它发送，每个属性的 ID 是分组的 ID、一个点、再加属性的名字。让它们保持不变。没有 `title` 的分组会得到一个由 ID 生成的标题。

### 编辑 {#editing}

带 `set` 的属性在 Cutaway 里可以像其他属性一样编辑。Cutaway 不会发送超出属性 `limits` 的值，`set` 只在主线程上收到通过了每项检查的值（种类、限制，只有 `acceptsNil` 时才有 `nil`）。

要拒绝一个值，就抛出错误。错误的描述显示在检查器里那个值的旁边，原来的值回来：

```swift
struct TooTall: LocalizedError {
    let height: Double
    var errorDescription: String? { "a bar can be at most \(Int(height)) points tall" }
}

.double("value", bar.value, section: .content, unit: .points, limits: [.atLeast(0)], set: { value in
    guard let value, value <= chart.bounds.height else {
        throw TooTall(height: chart.bounds.height)
    }
    chart.bars[index].value = value
})
```

`set` 改了 App 的一部分之后失败时，由 App 自己负责还原。

## 显示视图自己画的内容 {#show-what-a-view-draws-itself}

在 `draw(_:)` 里画出内容的视图，例如图表，对 UIKit 来说只是一个图层。虚拟节点让 Cutaway 把它的各个部分显示为层级里的节点，可以选中、检查：

```swift
CutawayServer.Description<SalesChartView>(
    virtualChildren: { chart in
        chart.bars.indices.map { index in
            let bar = chart.bars[index]
            return CutawayServer.VirtualNode(
                id: bar.id,
                type: SalesChartView.Bar.self,
                name: bar.label,
                frame: chart.frameOfBar(at: index),
                attributes: [
                    CutawayServer.AttributeGroup("bar", [
                        .string("label", bar.label, section: .identity),
                        .double("value", bar.value, section: .content, unit: .points)
                    ])
                ]
            )
        }
    }
)
```

| 参数 | 含义 |
|---|---|
| `id` | 节点代表什么，每次都是同一个值：用模型的标识，而不是下标。一个图层的节点里，同一个标识只出现一次；重复的节点连同它的子节点都会被去掉。Cutaway 会保留每个标识，直到连接结束或图层被释放，所以用 `String`、`Int`、`UUID` 这样的值，不要用对象 |
| `type` | 节点代表的东西的类型；Cutaway 显示它的名字。节点不代表任何 Swift 类型时，用 `typeName:` 给一个字符串 |
| `name` | 一个简短的标签，例如柱子的类别 |
| `frame` | 在父节点的坐标空间里：图层的 bounds，或原点为零的父节点的 frame |
| `transform` | 绕 `frame` 的中心施加 |
| `isHidden`、`opacity` | 与图层的相同 |
| `isCollapsedByDefault` | 节点一开始显示为折叠 |
| `attributes` | 选中节点时显示；可以像其他属性一样编辑。这个表达式只在 Cutaway 读节点的属性时求值，取层级时不求值 |
| `children` | 画在这个节点里面的节点 |

在 Cutaway 里，一个虚拟节点：

- 是图层列表里它的图层下面的一行，排在图层的子图层之前，标题是它的 `name`，类型是小字，并带有自己的图标；
- 在预览里画成虚线框，没有自己的图像：它的样子留在画它的那个图层的图像里；
- 可以选中、按名字搜索、聚焦，它的属性可以编辑。编辑之后，Cutaway 重新取画它的那个图层的图像；
- 没有可以导出的截图。

<Shot name="integrate-virtual-nodes" alt="Cutaway 里的 CutawayDemo 销售图表：柱子 North、South 和 East 是图层列表里的虚拟节点，预览里是它们的虚线框。" />

## 折叠与不截取 {#collapse-and-exclude}

```swift
// Shown collapsed when an inspection starts, with everything inside it.
CutawayServer.describe(FancyPickerView.self, CutawayServer.Description(isCollapsedByDefault: true))

// Never in an image: the card number stays on the device.
CutawayServer.describe(CardNumberView.self, CutawayServer.Description(isExcludedFromCapture: true))
```

- **默认折叠：** 一次检查开始时，这一行是折叠的，它下面的都不展开。你仍然可以展开它；**全部展开**和展开到第几层也会展开它。
- **不截取：** 这个视图和它里面的一切都不出现在任何图像里，用于敏感的内容，或截取很慢、截取不了的内容。Cutaway 把这块区域画上斜线并画出边框，不把它算进截图的进度，也不提供导出。它的属性照样读取。

## 给颜色起名 {#name-your-colors}

```swift
CutawayServer.registerColor(UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1), named: "brandBlue")
```

凡是属性的颜色等于一个登记过的颜色，Cutaway 就显示你起的名字；提示里仍给出十六进制值和这个颜色的其他名字。几个登记的颜色相等时，用最先登记的那个。再次登记一个名字会替换它的颜色，并保留它的位置。动态颜色按与它比较的视图的特征解析：在一个请求里每组特征解析一次，之后的每个请求重新解析。

## 一个完整的例子 {#a-complete-example}

CutawayServer 的演示 App 有一页用到这些扩展：一个自己画柱子的图表，每根柱子、每段柱子都有一个虚拟节点；一个不出现在任何图像里的卡号；一个登记的颜色。见 [CutawayServer 仓库](https://github.com/nothingsh/CutawayServer)里的 `Demo/CutawayDemo/DemoExtensionsViewController.swift`。

## 接下来 {#next}

<NextSteps :items="[
  { title: '在设备上的行为', text: '服务端在哪里监听，截取时会动到什么。', link: '/zh-Hans/integrate/on-device' },
  { title: '属性', text: 'Cutaway 怎样显示和编辑属性。', link: '/zh-Hans/guide/attributes' }
]" />
