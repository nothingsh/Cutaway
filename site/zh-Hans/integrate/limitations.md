---
description: CutawayServer 截取不到或找不到的东西，以及原因。
---

# 限制 {#limitations}

这些限制来自 iOS 的绘制方式，以及一个 App 能看到的自身的范围。

## 模糊、视频和 Metal 是空白的 {#blurs-video-and-metal-are-blank}

由系统的渲染服务在 App 进程之外合成的内容不在图像里：模糊效果、Metal 和视频图层等。CutawayServer 从 App 内部的图层树渲染每个图层，而那些内容不在其中。这些图层本身仍在层级里，带着它们的属性；只是它们的图是空的。

## 栏里的文字在图像里是白色的 {#bar-text-is-white-in-the-images}

渲染服务施加的滤镜同样不在图像里。在 iOS 26 上，导航栏、工具栏和标签栏里的文字和图标以单一的颜色绘制，常常是白色，渲染服务合成屏幕时，父图层上的一个滤镜才给了它们屏幕上的颜色。图像显示的是每个图层自己的内容，在那个滤镜之前。

`textColor` 一类的属性仍显示 App 设置的颜色。

## 颜色是 sRGB 的 {#colors-are-in-srgb}

颜色以 sRGB 发送，所以广色域（Display P3）的颜色会被截断为最接近的 sRGB 颜色。

## 成员变量名 {#member-variable-names}

Cutaway 标出持有一个图层或视图的成员变量，例如 `HomeViewController.titleLabel`。服务端通过比较持有者内存里的地址找到这些名字，不调用任何 getter，所以：

- 默认的（safe）`unowned` 属性持有的引用**找不到**；
- 集合（例如数组）里持有的引用**找不到**；
- `weak`、`unowned(unsafe)`、`lazy` 属性和泛型类的属性**找得到**。

## 环境的改写 {#environment-overrides}

[改写环境](/zh-Hans/guide/environment)有它自己的限制：

- iOS 17 之前只能改写外观（浅色或深色）；Cutaway 只提供 App 的服务端在那台设备上能改写的项。
- 文字大小只改变从特征环境取字体的内容，例如设了 `adjustsFontForContentSizeCategory` 的标签。
- 视图控制器或视图自己设的改写，例如它自己的 `overrideUserInterfaceStyle`，按 UIKit 的规则仍然优先，它下面的界面不会改变。

## 一次一个客户端 {#one-client-at-a-time}

服务端一次只服务一个 Cutaway。第一个连着时，第二个会被拒绝；第一个断开之后它就能连上。

## 接下来 {#next}

<NextSteps :items="[
  { title: '常见问题与故障排除', text: '更多关于“为什么这里是空白的？”的回答。', link: '/zh-Hans/resources/faq' },
  { title: '在设备上的行为', text: '截取时会动到并恢复什么。', link: '/zh-Hans/integrate/on-device' }
]" />
