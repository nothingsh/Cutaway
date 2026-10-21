// The home page's text in each language. Links are paths of the English site; HomePage.vue puts
// them in the page's language.

const en = {
  pill: ['New', '1.2: environment overrides, virtual nodes, Open in Xcode →'],
  title: 'Inspect iOS interfaces, layer by layer.',
  lead: 'Cutaway is a free Mac app that looks inside your running iOS app: every layer of the interface in 2D or spread apart in 3D, with its attributes and Auto Layout constraints. Change a value, and the app changes with it.',
  download: 'Download for macOS',
  start: 'Get started →',
  meta: (version: string) => `Version ${version} · macOS 14 or later · Free and open source`,
  overview: 'Cutaway inspecting an app in 3D: the layer tree, the layers spread apart, and the attributes of the selected layer.',
  steps: {
    title: 'Three steps to your first inspection',
    text: 'About ten minutes, most of it waiting for a build.',
    items: [
      { title: 'Add CutawayServer', text: 'Add the Swift package to your iOS app and start it at launch. It goes into Debug builds only.' },
      { title: 'Run your app', text: 'In the Simulator, or on an iPhone or iPad connected to your Mac with a cable.' },
      { title: 'Open Cutaway', text: 'Your app appears in the list within a few seconds. Choose it, and its layers arrive.' }
    ],
    more: 'Read the getting started guide →'
  },
  tour: {
    title: 'See how the interface is really built',
    text: 'Everything below works in the Simulator and on a device over USB, with any app that includes CutawayServer.'
  },
  features: [
    {
      kicker: 'Preview',
      title: 'Take the interface apart',
      text: 'Spread the layers apart in 3D and turn them with the trackpad to see what sits behind what. Collapse a subtree in the list and it folds back into one.',
      link: '/guide/preview',
      more: 'The preview',
      video: 'home-3d',
      alt: 'Turning the 3D preview, then widening the layer spacing'
    },
    {
      kicker: 'Measuring',
      title: 'Measure without a ruler',
      text: 'Select a layer, hold ⌥ and point at another, in the preview or in the layer list. The distances appear in points, in 2D and in 3D.',
      link: '/guide/measuring',
      more: 'Measuring',
      video: 'home-measure',
      alt: 'Holding Option over neighbouring layers, then over a row in the list'
    },
    {
      kicker: 'Attributes',
      title: 'Change it while it runs',
      text: 'Edit text, colors, opacity, insets and more. Each change is applied in the running app at once, and ⌘Z undoes it.',
      link: '/guide/attributes',
      more: 'Attributes',
      video: 'home-edit',
      alt: 'Dragging opacity and picking a color, then undoing'
    },
    {
      kicker: 'Auto Layout',
      title: 'Follow the constraints',
      text: 'See every constraint that refers to a view, which ones are not in effect, and where the other end is. Click the other end to go to it.',
      link: '/guide/constraints',
      more: 'Constraints',
      video: 'home-constraints',
      alt: 'Pointing at constraints; their other ends light up in the preview'
    },
    {
      kicker: 'Environment',
      badge: 'Needs CutawayServer 1.2',
      title: 'Try dark mode and larger text',
      text: 'Override the app’s appearance, text size, layout direction and size classes from the toolbar, and the preview follows, without opening the Simulator’s settings.',
      link: '/guide/environment',
      more: 'Environment',
      video: 'home-environment',
      alt: 'Switching to Dark, then to a larger text size'
    },
    {
      kicker: 'Archives',
      title: 'Keep what you found',
      text: 'Save an inspection as a .cutaway file and open it later on any Mac, without the device: the tree, screenshots, attributes and constraints are all there.',
      link: '/guide/archives',
      more: 'Archives and export',
      video: 'home-archive',
      alt: 'Saving an archive, then opening it in its own window'
    }
  ] as { kicker: string; badge?: string; title: string; text: string; link: string; more: string; video: string; alt: string }[],
  extras: [
    { title: 'Open in Xcode', text: 'Jump from a class to its declaration in your project.', link: '/guide/source' },
    { title: 'Copy as LLDB', text: 'Paste a command that reaches the same object in the debugger.', link: '/guide/source#copy-an-lldb-command' },
    { title: 'Filter and focus', text: 'Find a layer by name, then show only its subtree.', link: '/guide/hierarchy' },
    { title: 'Your app’s own details', text: 'Attribute groups, color names and virtual nodes from your code.', link: '/integrate/customizing' },
    { title: 'Export as PNG', text: 'A layer’s image, alone or with its sublayers, at the device’s scale.', link: '/guide/archives#export-a-screenshot' },
    { title: 'Five languages', text: 'English, Simplified and Traditional Chinese, Japanese and Korean.', link: '/guide/settings' }
  ],
  speed: {
    title: 'Fast with ten thousand layers',
    text: 'Every build is held to these limits by the test suite, on a generated tree of 10,000 layers shaped like a real app.',
    stats: [
      { value: '2 s', text: 'from the tree arriving to the list on screen' },
      { value: '16 ms', text: 'for a new frame while you turn the camera' },
      { value: '100 ms', text: 'from selecting a row to the preview and inspector following' }
    ],
    more: 'How Cutaway stays fast →'
  },
  privacy: {
    title: 'Stays between your Mac and your app',
    more: 'Privacy and security →',
    points: [
      'Cutaway talks to simulators over the loopback address and to devices over the USB cable, and to nothing else.',
      'No account, no analytics, no crash reports. Checking for updates asks GitHub for the list of releases and sends nothing about your Mac.',
      'CutawayServer listens on 127.0.0.1 only and is left out of Release builds unless you opt in.'
    ]
  },
  parts: {
    title: 'Three open-source parts',
    text: 'The Mac app and the iOS SDK share no code, only a versioned protocol, so either side can be read, tested or replaced on its own.',
    items: [
      {
        title: 'Cutaway',
        text: 'The macOS app. Finds your apps, draws their layers and edits their attributes. Swift, AppKit and Metal.',
        meta: 'GPL-3.0 · macOS 14 or later',
        links: [
          { text: 'Guide', link: '/guide/getting-started' },
          { text: 'GitHub', href: 'https://github.com/nothingsh/Cutaway' }
        ]
      },
      {
        title: 'CutawayServer',
        text: 'The iOS SDK you add to your app. Captures layers, images and attributes when Cutaway asks. Pure Swift, no dependencies.',
        meta: 'MIT · iOS 13 or later · Swift Package Manager',
        links: [
          { text: 'Integrate', link: '/integrate/' },
          { text: 'GitHub', href: 'https://github.com/nothingsh/CutawayServer' }
        ]
      },
      {
        title: 'Cutaway Protocol',
        text: 'The FlatBuffers protocol between them: a numbered specification, the schema, and fixtures for testing either end.',
        meta: 'MIT · version 1.2',
        links: [
          { text: 'Protocol', link: '/protocol/' },
          { text: 'GitHub', href: 'https://github.com/nothingsh/CutawayProtocol' }
        ]
      }
    ] as { title: string; text: string; meta: string; links: { text: string; link?: string; href?: string }[] }[]
  },
  closing: {
    title: 'Ready to look inside?',
    releases: 'All releases and checksums'
  }
}

export type HomeText = typeof en

const zh: HomeText = {
  pill: ['新', '1.2：改写环境、虚拟节点、在 Xcode 中打开 →'],
  title: '逐层查看 iOS 界面。',
  lead: 'Cutaway 是一个免费的 Mac App，让你看到正在运行的 iOS App 内部：界面的每一个图层，以 2D 平铺或在 3D 中分层展开，连同它的属性和 Auto Layout 约束。改一个值，App 随之改变。',
  download: '下载 macOS 版',
  start: '开始使用 →',
  meta: (version: string) => `版本 ${version} · macOS 14 或更新版本 · 免费、开源`,
  overview: 'Cutaway 在 3D 中检查一个 App：图层树、分层展开的图层，以及所选图层的属性。',
  steps: {
    title: '三步完成第一次检查',
    text: '约十分钟，大部分时间在等构建。',
    items: [
      { title: '加入 CutawayServer', text: '把这个 Swift 包加进你的 iOS App，并在启动时开启它。它只进入 Debug 构建。' },
      { title: '运行你的 App', text: '在模拟器里，或在用线缆连接 Mac 的 iPhone、iPad 上。' },
      { title: '打开 Cutaway', text: '几秒钟内你的 App 就会出现在列表里。选中它，图层随即到来。' }
    ],
    more: '阅读开始使用指南 →'
  },
  tour: {
    title: '看清界面究竟是怎样搭起来的',
    text: '下面的一切在模拟器里和经 USB 连接的设备上都可用，适用于任何集成了 CutawayServer 的 App。'
  },
  features: [
    {
      kicker: '预览',
      title: '把界面拆开来看',
      text: '在 3D 中把图层分开，用触控板转动，看清谁在谁后面。在列表里折叠一棵子树，它就合回一层。',
      link: '/guide/preview',
      more: '预览',
      video: 'home-3d',
      alt: '转动 3D 预览，然后加大层间距'
    },
    {
      kicker: '测距',
      title: '不用尺子也能量',
      text: '选中一个图层，按住 ⌥ 指向另一个，在预览里或图层列表里都可以。距离以点为单位显示，2D 和 3D 下都有。',
      link: '/guide/measuring',
      more: '测距',
      video: 'home-measure',
      alt: '按住 Option 依次指向相邻的图层，然后指向列表里的一行'
    },
    {
      kicker: '属性',
      title: '在运行中修改',
      text: '编辑文字、颜色、不透明度、边距等。每项修改立即作用于运行中的 App，⌘Z 可以撤销。',
      link: '/guide/attributes',
      more: '属性',
      video: 'home-edit',
      alt: '拖动不透明度、挑选颜色，然后撤销'
    },
    {
      kicker: 'Auto Layout',
      title: '顺着约束找下去',
      text: '看到指向一个视图的每一条约束、哪些没有生效、另一端在哪里。点按另一端就跳过去。',
      link: '/guide/constraints',
      more: '约束',
      video: 'home-constraints',
      alt: '依次指向约束，它们的另一端在预览里亮起'
    },
    {
      kicker: '环境',
      badge: '需要 CutawayServer 1.2',
      title: '试试深色模式和更大的文字',
      text: '从工具栏改写 App 的外观、文字大小、布局方向和尺寸类别，预览随之更新，不用打开模拟器的设置。',
      link: '/guide/environment',
      more: '环境',
      video: 'home-environment',
      alt: '切换到深色，然后换成更大的文字'
    },
    {
      kicker: '存档',
      title: '留下你的发现',
      text: '把一次检查存为 .cutaway 文件，以后在任何一台 Mac 上打开，不用连设备：图层树、截图、属性和约束都在。',
      link: '/guide/archives',
      more: '存档与导出',
      video: 'home-archive',
      alt: '存储一份存档，然后在它自己的窗口里打开'
    }
  ],
  extras: [
    { title: '在 Xcode 中打开', text: '从一个类跳到它在你的项目里的声明。', link: '/guide/source' },
    { title: '拷贝 LLDB 命令', text: '贴进调试器，就能拿到同一个对象。', link: '/guide/source#copy-an-lldb-command' },
    { title: '过滤与聚焦', text: '按名字找到一个图层，然后只看它的子树。', link: '/guide/hierarchy' },
    { title: '你的 App 自己的信息', text: '来自你的代码的属性分组、颜色名和虚拟节点。', link: '/integrate/customizing' },
    { title: '导出为 PNG', text: '一个图层的图像，单独或连同子图层，按设备的比例。', link: '/guide/archives#export-a-screenshot' },
    { title: '五种语言', text: '英文、简体中文、繁体中文、日文和韩文。', link: '/guide/settings' }
  ],
  speed: {
    title: '一万个图层也很快',
    text: '每次构建都由测试守住这些指标，测试用的是一棵按真实 App 的形状生成的 10,000 个图层的树。',
    stats: [
      { value: '2 秒', text: '从图层树到达到列表显示出来' },
      { value: '16 毫秒', text: '转动相机时画出新的一帧' },
      { value: '100 毫秒', text: '从选中一行到预览和检查器跟上' }
    ],
    more: 'Cutaway 怎样保持快速 →'
  },
  privacy: {
    title: '只在你的 Mac 和你的 App 之间',
    more: '隐私与安全 →',
    points: [
      'Cutaway 经回环地址与模拟器通信，经 USB 线缆与设备通信，不与其他任何地方通信。',
      '没有账户，没有统计，没有崩溃报告。检查更新时只向 GitHub 要版本列表，不发送你的 Mac 的任何信息。',
      'CutawayServer 只监听 127.0.0.1，并且不进入 Release 构建，除非你主动打开。'
    ]
  },
  parts: {
    title: '三个开源的部分',
    text: 'Mac App 与 iOS SDK 不共享代码，只共享一个带版本的协议，所以任何一边都可以单独阅读、测试或替换。',
    items: [
      {
        title: 'Cutaway',
        text: 'macOS App。找到你的 App，画出它们的图层，编辑它们的属性。Swift、AppKit 和 Metal。',
        meta: 'GPL-3.0 · macOS 14 或更新版本',
        links: [
          { text: '指南', link: '/guide/getting-started' },
          { text: 'GitHub', href: 'https://github.com/nothingsh/Cutaway' }
        ]
      },
      {
        title: 'CutawayServer',
        text: '加进你的 App 的 iOS SDK。Cutaway 请求时截取图层、图像和属性。纯 Swift，没有依赖。',
        meta: 'MIT · iOS 13 或更新版本 · Swift Package Manager',
        links: [
          { text: '集成', link: '/integrate/' },
          { text: 'GitHub', href: 'https://github.com/nothingsh/CutawayServer' }
        ]
      },
      {
        title: 'Cutaway Protocol',
        text: '两者之间的 FlatBuffers 协议：带编号的规范、schema，以及用来测试任何一端的夹具。',
        meta: 'MIT · 版本 1.2',
        links: [
          { text: '协议', link: '/protocol/' },
          { text: 'GitHub', href: 'https://github.com/nothingsh/CutawayProtocol' }
        ]
      }
    ]
  },
  closing: {
    title: '准备好看看里面了吗？',
    releases: '全部版本与校验和'
  }
}

export default { en, 'zh-Hans': zh }
