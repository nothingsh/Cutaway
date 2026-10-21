import { defineConfig } from 'vitepress'

// The site is published at https://nothingsh.github.io/Cutaway/ by .github/workflows/site.yml.
const origin = 'https://nothingsh.github.io'
const base = '/Cutaway/'
const repository = 'https://github.com/nothingsh/Cutaway'
// The release the site describes. The download links and the pages' version notes read it.
const version = '1.2.0'

const guide = [
  {
    text: 'Start',
    items: [
      { text: 'Getting started', link: '/guide/getting-started' },
      { text: 'Connecting to apps', link: '/guide/connecting' }
    ]
  },
  {
    text: 'Explore',
    items: [
      { text: 'The layer list', link: '/guide/hierarchy' },
      { text: 'The preview', link: '/guide/preview' },
      { text: 'Measuring', link: '/guide/measuring' }
    ]
  },
  {
    text: 'Inspect',
    items: [
      { text: 'Attributes', link: '/guide/attributes' },
      { text: 'Constraints', link: '/guide/constraints' },
      { text: 'Environment', link: '/guide/environment' },
      { text: 'Source code', link: '/guide/source' }
    ]
  },
  {
    text: 'Keep',
    items: [{ text: 'Archives and export', link: '/guide/archives' }]
  },
  {
    text: 'Reference',
    items: [
      { text: 'Settings', link: '/guide/settings' },
      { text: 'Keyboard shortcuts', link: '/guide/shortcuts' }
    ]
  }
]

const integrate = [
  {
    text: 'Integrate',
    items: [
      { text: 'Installation', link: '/integrate/' },
      { text: 'Debug and Release builds', link: '/integrate/builds' },
      { text: 'Customizing what Cutaway shows', link: '/integrate/customizing' },
      { text: 'Behavior on the device', link: '/integrate/on-device' },
      { text: 'Limitations', link: '/integrate/limitations' }
    ]
  }
]

const protocol = [
  {
    text: 'Protocol',
    items: [
      { text: 'Overview', link: '/protocol/' },
      { text: 'Versions and compatibility', link: '/protocol/versions' },
      { text: 'Implementing a peer', link: '/protocol/implementing' },
      { text: 'Specification', link: '/protocol/spec' }
    ]
  }
]

const resources = [
  {
    text: 'Resources',
    items: [
      { text: 'FAQ and troubleshooting', link: '/resources/faq' },
      { text: 'Privacy and security', link: '/resources/privacy' },
      { text: 'Performance', link: '/resources/performance' },
      { text: 'Release notes', link: '/resources/releases' },
      { text: 'Roadmap', link: '/resources/roadmap' },
      { text: 'Contributing', link: '/resources/contributing' }
    ]
  }
]

// The same sidebars in Simplified Chinese, for the pages under zh-Hans/.
const zhGuide = [
  {
    text: '开始',
    items: [
      { text: '开始使用', link: '/zh-Hans/guide/getting-started' },
      { text: '连接 App', link: '/zh-Hans/guide/connecting' }
    ]
  },
  {
    text: '浏览',
    items: [
      { text: '图层列表', link: '/zh-Hans/guide/hierarchy' },
      { text: '预览', link: '/zh-Hans/guide/preview' },
      { text: '测距', link: '/zh-Hans/guide/measuring' }
    ]
  },
  {
    text: '检查',
    items: [
      { text: '属性', link: '/zh-Hans/guide/attributes' },
      { text: '约束', link: '/zh-Hans/guide/constraints' },
      { text: '环境', link: '/zh-Hans/guide/environment' },
      { text: '源代码', link: '/zh-Hans/guide/source' }
    ]
  },
  {
    text: '保留',
    items: [{ text: '存档与导出', link: '/zh-Hans/guide/archives' }]
  },
  {
    text: '参考',
    items: [
      { text: '设置', link: '/zh-Hans/guide/settings' },
      { text: '键盘快捷键', link: '/zh-Hans/guide/shortcuts' }
    ]
  }
]

const zhIntegrate = [
  {
    text: '集成',
    items: [
      { text: '安装', link: '/zh-Hans/integrate/' },
      { text: 'Debug 与 Release 构建', link: '/zh-Hans/integrate/builds' },
      { text: '定制 Cutaway 显示的内容', link: '/zh-Hans/integrate/customizing' },
      { text: '在设备上的行为', link: '/zh-Hans/integrate/on-device' },
      { text: '限制', link: '/zh-Hans/integrate/limitations' }
    ]
  }
]

const zhProtocol = [
  {
    text: '协议',
    items: [
      { text: '概览', link: '/zh-Hans/protocol/' },
      { text: '版本与兼容', link: '/zh-Hans/protocol/versions' },
      { text: '实现一端', link: '/zh-Hans/protocol/implementing' },
      { text: '规范', link: '/zh-Hans/protocol/spec' }
    ]
  }
]

const zhResources = [
  {
    text: '资源',
    items: [
      { text: '常见问题与故障排除', link: '/zh-Hans/resources/faq' },
      { text: '隐私与安全', link: '/zh-Hans/resources/privacy' },
      { text: '性能', link: '/zh-Hans/resources/performance' },
      { text: '版本记录', link: '/zh-Hans/resources/releases' },
      { text: '路线图', link: '/zh-Hans/resources/roadmap' },
      { text: '参与贡献', link: '/zh-Hans/resources/contributing' }
    ]
  }
]

export default defineConfig({
  base,
  title: 'Cutaway',
  cleanUrls: true,
  srcExclude: ['**/README.md', 'MEDIA.md'],
  sitemap: { hostname: origin + base },
  head: [
    ['link', { rel: 'icon', type: 'image/png', sizes: '64x64', href: base + 'favicon.png' }],
    ['link', { rel: 'apple-touch-icon', href: base + 'apple-touch-icon.png' }],
    ['meta', { name: 'theme-color', content: '#2f5bd8' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:site_name', content: 'Cutaway' }],
    ['meta', { property: 'og:image', content: origin + base + 'social.png' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }]
  ],
  transformPageData(page) {
    const title = page.frontmatter.title ?? page.title
    page.frontmatter.head ??= []
    page.frontmatter.head.push(
      ['meta', { property: 'og:title', content: title ? `${title} | Cutaway` : 'Cutaway' }],
      ['meta', { property: 'og:description', content: page.frontmatter.description ?? page.description }]
    )
  },
  markdown: {
    theme: { light: 'github-light', dark: 'github-dark' }
  },
  locales: {
    root: {
      label: 'English',
      lang: 'en',
      description: 'Inspect iOS interfaces, layer by layer: a free Mac app that shows a running iOS app’s layers in 2D and 3D, with their attributes and Auto Layout constraints.',
      themeConfig: {
        nav: [
          { text: 'Guide', link: '/guide/getting-started', activeMatch: '^/guide/' },
          { text: 'Integrate', link: '/integrate/', activeMatch: '^/integrate/' },
          { text: 'Protocol', link: '/protocol/', activeMatch: '^/protocol/' },
          { text: 'Resources', link: '/resources/faq', activeMatch: '^/resources/' },
          { text: 'Download', link: `${repository}/releases/latest` }
        ],
        sidebar: {
          '/guide/': guide,
          '/integrate/': integrate,
          '/protocol/': protocol,
          '/resources/': resources
        },
        outline: { level: [2, 3], label: 'On this page' },
        editLink: {
          pattern: `${repository}/edit/main/site/:path`,
          text: 'Edit this page on GitHub'
        },
        docFooter: { prev: 'Previous', next: 'Next' },
        footer: {
          message: 'Cutaway is free software under the GPL-3.0. CutawayServer and the Cutaway Protocol are under the MIT License.',
          copyright: 'Written for Cutaway 1.2'
        }
      }
    },
    'zh-Hans': {
      label: '简体中文',
      lang: 'zh-Hans',
      description: '逐层查看 iOS 界面：一个免费的 Mac App，以 2D 和 3D 显示运行中的 iOS App 的图层，连同它们的属性和 Auto Layout 约束。',
      themeConfig: {
        nav: [
          { text: '指南', link: '/zh-Hans/guide/getting-started', activeMatch: '^/zh-Hans/guide/' },
          { text: '集成', link: '/zh-Hans/integrate/', activeMatch: '^/zh-Hans/integrate/' },
          { text: '协议', link: '/zh-Hans/protocol/', activeMatch: '^/zh-Hans/protocol/' },
          { text: '资源', link: '/zh-Hans/resources/faq', activeMatch: '^/zh-Hans/resources/' },
          { text: '下载', link: `${repository}/releases/latest` }
        ],
        sidebar: {
          '/zh-Hans/guide/': zhGuide,
          '/zh-Hans/integrate/': zhIntegrate,
          '/zh-Hans/protocol/': zhProtocol,
          '/zh-Hans/resources/': zhResources
        },
        outline: { level: [2, 3], label: '本页内容' },
        editLink: {
          pattern: `${repository}/edit/main/site/:path`,
          text: '在 GitHub 上编辑此页'
        },
        docFooter: { prev: '上一页', next: '下一页' },
        footer: {
          message: 'Cutaway 是采用 GPL-3.0 许可证的自由软件。CutawayServer 与 Cutaway Protocol 采用 MIT 许可证。',
          copyright: '按 Cutaway 1.2 编写'
        },
        langMenuLabel: '语言',
        returnToTopLabel: '回到顶部',
        sidebarMenuLabel: '目录',
        darkModeSwitchLabel: '外观',
        lightModeSwitchTitle: '切换到浅色外观',
        darkModeSwitchTitle: '切换到深色外观',
        skipToContentLabel: '跳到正文',
        notFound: {
          title: '找不到这一页',
          quote: '它可能已被移走，或者网址有误。',
          linkLabel: '回到首页',
          linkText: '回到首页'
        }
      }
    }
  },
  themeConfig: {
    cutaway: {
      version,
      download: `${repository}/releases/download/v${version}/Cutaway-${version}.dmg`,
      releases: `${repository}/releases`
    },
    logo: { src: '/logo.png', alt: '' },
    search: {
      provider: 'local',
      options: {
        // Chinese has no spaces between words: split it into words as the browser does, and
        // everything else at spaces and punctuation as MiniSearch does by default. Serialized
        // into the page, so it must not refer to anything outside itself.
        miniSearch: {
          options: {
            tokenize: (text: string) => {
              const words = new Intl.Segmenter('zh-Hans', { granularity: 'word' })
              return text
                .split(/[\n\r\p{Z}\p{P}]+/u)
                .flatMap((part) =>
                  /\p{Script=Han}/u.test(part)
                    ? [...words.segment(part)].filter((word) => word.isWordLike).map((word) => word.segment)
                    : [part]
                )
            }
          }
        },
        locales: {
          'zh-Hans': {
            translations: {
              button: { buttonText: '搜索', buttonAriaLabel: '搜索' },
              modal: {
                displayDetails: '显示详细列表',
                resetButtonTitle: '清除查询',
                backButtonTitle: '关闭搜索',
                noResultsText: '没有结果',
                footer: {
                  selectText: '选择',
                  selectKeyAriaLabel: '回车',
                  navigateText: '切换',
                  navigateUpKeyAriaLabel: '上箭头',
                  navigateDownKeyAriaLabel: '下箭头',
                  closeText: '关闭',
                  closeKeyAriaLabel: 'Esc'
                }
              }
            }
          }
        }
      }
    },
    socialLinks: [{ icon: 'github', link: repository }],
    externalLinkIcon: true
  }
})
