---
description: CutawayServer 截取不到或找不到的东西，以及原因。
---

# 限制 {#limitations}

这些限制来自 iOS 的绘制方式，以及一个 App 能看到的自身的范围。

## 只有系统才画得出的内容 {#what-only-the-system-draws}

CutawayServer 1.3 从 App 合成好的结果取窗口的画面，以及含模糊、Liquid Glass 或颜色滤镜的子树的画面，所以这些效果在 2D 和折叠的图层上看得到。图层自己的图仍从 App 内部的图层树渲染，没有这些效果，3D 下展开的图层显示的就是它。状态栏不属于 App，不在任何图像里。

采样背后内容的效果（例如玻璃）在子树的画面里可能与屏幕不同。有被排除的视图显示时，或窗口半透明时，服务端改为绘制图层。视频和 Metal 的内容仍可能是空白的。服务端低于 1.3 时，所有图像都从图层绘制。

## 栏里的文字在图层自己的图里可能是白色 {#bar-text-can-be-white-in-a-layer-s-own-image}

在 iOS 26 上，导航栏、工具栏和标签栏里的文字和图标以单一的颜色绘制，常常是白色，渲染服务合成屏幕时，父图层上的一个滤镜才给了它们屏幕上的颜色。图层自己的图显示的是滤镜之前的内容。窗口的画面和折叠的栏的画面颜色是对的。

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
