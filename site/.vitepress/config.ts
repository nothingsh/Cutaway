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

export default defineConfig({
  base,
  lang: 'en',
  title: 'Cutaway',
  description: 'Inspect iOS interfaces, layer by layer: a free Mac app that shows a running iOS app’s layers in 2D and 3D, with their attributes and Auto Layout constraints.',
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
  themeConfig: {
    cutaway: {
      version,
      download: `${repository}/releases/download/v${version}/Cutaway-${version}.dmg`,
      releases: `${repository}/releases`
    },
    logo: { src: '/logo.png', alt: '' },
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
    search: { provider: 'local' },
    socialLinks: [{ icon: 'github', link: repository }],
    editLink: {
      pattern: `${repository}/edit/main/site/:path`,
      text: 'Edit this page on GitHub'
    },
    docFooter: { prev: 'Previous', next: 'Next' },
    footer: {
      message: 'Cutaway is free software under the GPL-3.0. CutawayServer and the Cutaway Protocol are under the MIT License.',
      copyright: 'Written for Cutaway 1.2'
    },
    externalLinkIcon: true
  }
})
