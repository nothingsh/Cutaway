<script setup lang="ts">
// The home page, for someone who has just heard of Cutaway: what it is, how to start, what it
// does, and why it can be trusted. Follows the canvas board "Website (proposal)".
import { useData, withBase } from 'vitepress'
import PartsDiagram from './PartsDiagram.vue'
import Loop from './Loop.vue'

const { theme } = useData()
const cutaway = theme.value.cutaway as { version: string; download: string; releases: string }

const features = [
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
]

const extras = [
  { title: 'Open in Xcode', text: 'Jump from a class to its declaration in your project.', link: '/guide/source' },
  { title: 'Copy as LLDB', text: 'Paste a command that reaches the same object in the debugger.', link: '/guide/source#copy-an-lldb-command' },
  { title: 'Filter and focus', text: 'Find a layer by name, then show only its subtree.', link: '/guide/hierarchy' },
  { title: 'Your app’s own details', text: 'Attribute groups, color names and virtual nodes from your code.', link: '/integrate/customizing' },
  { title: 'Export as PNG', text: 'A layer’s image, alone or with its sublayers, at the device’s scale.', link: '/guide/archives#export-a-screenshot' },
  { title: 'Five languages', text: 'English, Simplified and Traditional Chinese, Japanese and Korean.', link: '/guide/settings' }
]

const stats = [
  { value: '2 s', text: 'from the tree arriving to the list on screen' },
  { value: '16 ms', text: 'for a new frame while you turn the camera' },
  { value: '100 ms', text: 'from selecting a row to the preview and inspector following' }
]

const parts = [
  {
    title: 'Cutaway',
    text: 'The macOS app. Finds your apps, draws their layers and edits their attributes. Swift, AppKit and Metal.',
    meta: 'GPL-3.0 · macOS 14 or later',
    links: [
      { text: 'Guide', href: withBase('/guide/getting-started') },
      { text: 'GitHub', href: 'https://github.com/nothingsh/Cutaway' }
    ]
  },
  {
    title: 'CutawayServer',
    text: 'The iOS SDK you add to your app. Captures layers, images and attributes when Cutaway asks. Pure Swift, no dependencies.',
    meta: 'MIT · iOS 13 or later · Swift Package Manager',
    links: [
      { text: 'Integrate', href: withBase('/integrate/') },
      { text: 'GitHub', href: 'https://github.com/nothingsh/CutawayServer' }
    ]
  },
  {
    title: 'Cutaway Protocol',
    text: 'The FlatBuffers protocol between them: a numbered specification, the schema, and fixtures for testing either end.',
    meta: 'MIT · version 1.2',
    links: [
      { text: 'Protocol', href: withBase('/protocol/') },
      { text: 'GitHub', href: 'https://github.com/nothingsh/CutawayProtocol' }
    ]
  }
]
</script>

<template>
  <div class="home">
    <section class="hero">
      <a class="pill" :href="withBase('/resources/releases')"><b>New</b>1.2: environment overrides, virtual nodes, Open in Xcode →</a>
      <h1>Inspect iOS interfaces, layer by layer.</h1>
      <p class="lead">
        Cutaway is a free Mac app that looks inside your running iOS app: every layer of the interface in 2D or spread apart in 3D,
        with its attributes and Auto Layout constraints. Change a value, and the app changes with it.
      </p>
      <div class="actions">
        <a class="button primary" :href="cutaway.download">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M8 2v9M4 7.5 L8 11.5 L12 7.5M3 14h10" /></svg>
          Download for macOS
        </a>
        <a class="button secondary" :href="withBase('/guide/getting-started')">Get started →</a>
      </div>
      <p class="meta">Version {{ cutaway.version }} · macOS 14 or later · Free and open source</p>
      <div class="product">
        <img class="light-only" :src="withBase('/media/home-overview-light.png')" width="1600" height="1000" fetchpriority="high"
          alt="Cutaway inspecting an app in 3D: the layer tree, the layers spread apart, and the attributes of the selected layer." />
        <img class="dark-only" :src="withBase('/media/home-overview-dark.png')" width="1600" height="1000"
          alt="Cutaway inspecting an app in 3D: the layer tree, the layers spread apart, and the attributes of the selected layer." />
      </div>
    </section>

    <section class="band steps">
      <div class="container">
        <header class="center">
          <h2>Three steps to your first inspection</h2>
          <p class="body">About ten minutes, most of it waiting for a build.</p>
        </header>
        <div class="grid three">
          <div class="card">
            <span class="num">1</span>
            <h3>Add CutawayServer</h3>
            <p class="body">Add the Swift package to your iOS app and start it at launch. It goes into Debug builds only.</p>
            <pre><code>CutawayServer.start()</code></pre>
          </div>
          <div class="card">
            <span class="num">2</span>
            <h3>Run your app</h3>
            <p class="body">In the Simulator, or on an iPhone or iPad connected to your Mac with a cable.</p>
          </div>
          <div class="card">
            <span class="num">3</span>
            <h3>Open Cutaway</h3>
            <p class="body">Your app appears in the list within a few seconds. Choose it, and its layers arrive.</p>
          </div>
        </div>
        <a class="more center-self" :href="withBase('/guide/getting-started')">Read the getting started guide →</a>
      </div>
    </section>

    <section class="tour">
      <div class="container">
        <header class="center">
          <h2>See how the interface is really built</h2>
          <p class="body narrow">Everything below works in the Simulator and on a device over USB, with any app that includes CutawayServer.</p>
        </header>
        <div v-for="(feature, index) in features" :key="feature.title" class="feature" :class="{ flip: index % 2 === 1 }">
          <div class="text">
            <div class="kicker-row">
              <span class="kicker">{{ feature.kicker }}</span>
              <span v-if="feature.badge" class="badge">{{ feature.badge }}</span>
            </div>
            <h3>{{ feature.title }}</h3>
            <p class="body">{{ feature.text }}</p>
            <a class="more" :href="withBase(feature.link)">{{ feature.more }} →</a>
          </div>
          <Loop class="media" :name="feature.video" :alt="feature.alt" />
        </div>
        <div class="grid three extras">
          <a v-for="extra in extras" :key="extra.title" class="extra" :href="withBase(extra.link)">
            <b>{{ extra.title }}</b>
            <span>{{ extra.text }}</span>
          </a>
        </div>
      </div>
    </section>

    <section class="band">
      <div class="container">
        <header>
          <h2>Fast with ten thousand layers</h2>
          <p class="body narrow">Every build is held to these limits by the test suite, on a generated tree of 10,000 layers shaped like a real app.</p>
        </header>
        <div class="grid three">
          <div v-for="stat in stats" :key="stat.value" class="stat">
            <b>{{ stat.value }}</b>
            <span class="body">{{ stat.text }}</span>
          </div>
        </div>
        <a class="more" :href="withBase('/resources/performance')">How Cutaway stays fast →</a>
      </div>
    </section>

    <section>
      <div class="container privacy">
        <div class="privacy-title">
          <svg width="36" height="36" viewBox="0 0 36 36" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="7" y="15" width="22" height="16" rx="4" /><path d="M12 15v-4a6 6 0 0 1 12 0v4" /></svg>
          <h2>Stays between your Mac and your app</h2>
          <a class="more" :href="withBase('/resources/privacy')">Privacy and security →</a>
        </div>
        <ul class="checks">
          <li>Cutaway talks to simulators over the loopback address and to devices over the USB cable, and to nothing else.</li>
          <li>No account, no analytics, no crash reports. Checking for updates asks GitHub for the list of releases and sends nothing about your Mac.</li>
          <li>CutawayServer listens on 127.0.0.1 only and is left out of Release builds unless you opt in.</li>
        </ul>
      </div>
    </section>

    <section class="band">
      <div class="container">
        <header class="center">
          <h2>Three open-source parts</h2>
          <p class="body narrow">The Mac app and the iOS SDK share no code, only a versioned protocol, so either side can be read, tested or replaced on its own.</p>
        </header>
        <PartsDiagram />
        <div class="grid three">
          <div v-for="part in parts" :key="part.title" class="card">
            <h3>{{ part.title }}</h3>
            <p class="body grow">{{ part.text }}</p>
            <p class="meta">{{ part.meta }}</p>
            <div class="links">
              <a v-for="link in part.links" :key="link.text" class="more" :href="link.href">{{ link.text }} →</a>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section class="closing">
      <h2>Ready to look inside?</h2>
      <div class="actions">
        <a class="button primary" :href="cutaway.download">Download for macOS</a>
        <a class="button secondary" :href="withBase('/guide/getting-started')">Get started →</a>
      </div>
      <p class="meta"><a :href="cutaway.releases">All releases and checksums</a></p>
    </section>
  </div>
</template>

<style scoped>
.home {
  --gutter: 24px;
  color: var(--vp-c-text-1);
}

.container {
  display: flex;
  flex-direction: column;
  gap: 32px;
  max-width: 1080px;
  margin: 0 auto;
  padding: 88px var(--gutter);
}

section h2 {
  margin: 0;
  font-size: 32px;
  line-height: 1.15;
  letter-spacing: -0.015em;
  font-weight: 700;
}

h3 {
  margin: 0;
  font-size: 22px;
  line-height: 1.25;
  font-weight: 650;
}

header {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.center {
  align-items: center;
  text-align: center;
}

.center-self {
  align-self: center;
}

.narrow {
  max-width: 600px;
}

.body {
  margin: 0;
  color: var(--vp-c-text-2);
  font-size: 15.5px;
  line-height: 1.6;
}

.meta {
  margin: 0;
  color: var(--vp-c-text-3);
  font-size: 13px;
}

.more {
  color: var(--vp-c-brand-1);
  font-size: 15px;
  font-weight: 600;
  text-decoration: none;
}

.more:hover {
  text-decoration: underline;
}

.hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 22px;
  padding: 64px var(--gutter) 0;
  text-align: center;
}

.pill {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 5px 12px 5px 6px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 999px;
  background: var(--cw-soft);
  color: var(--vp-c-text-2);
  font-size: 13px;
  text-decoration: none;
}

.pill b {
  padding: 2px 7px;
  border-radius: 999px;
  background: var(--vp-button-brand-bg);
  color: #fff;
  font-size: 11px;
}

.hero h1 {
  max-width: 820px;
  margin: 0;
  font-size: 54px;
  text-wrap: balance;
  line-height: 1.06;
  letter-spacing: -0.025em;
  font-weight: 700;
}

.lead {
  max-width: 700px;
  text-wrap: pretty;
  margin: 0;
  color: var(--vp-c-text-2);
  font-size: 19px;
  line-height: 1.55;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 12px;
}

.button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  height: 44px;
  padding: 0 20px;
  border-radius: 10px;
  font-size: 15px;
  font-weight: 600;
  text-decoration: none;
  transition: background-color 0.2s;
}

.button.primary {
  background: var(--vp-button-brand-bg);
  color: #fff;
}

.button.primary:hover {
  background: var(--vp-button-brand-hover-bg);
}

.button.secondary {
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-brand-1);
}

.product {
  width: 100%;
  max-width: 960px;
  margin: 26px 0 -40px;
  position: relative;
  z-index: 1;
}

.product img {
  display: block;
  width: 100%;
  height: auto;
  /* The picture is the window with its own rounded corners; this follows them at any width. */
  border-radius: 2.75% / 4.4%;
  box-shadow: var(--cw-shadow);
}

.dark .light-only,
html:not(.dark) .dark-only {
  display: none;
}

.band {
  border-top: 1px solid var(--vp-c-divider);
  border-bottom: 1px solid var(--vp-c-divider);
  background: var(--cw-soft);
}

.steps .container {
  padding-top: 112px;
}

.grid {
  display: grid;
  gap: 16px;
}

.grid.three {
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.card {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 22px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 14px;
  background: var(--vp-c-bg);
}

.card h3 {
  font-size: 18px;
}

.card .body {
  font-size: 14.5px;
}

.card pre {
  margin: 0;
  padding: 10px 12px;
  border-radius: 8px;
  background: var(--vp-code-block-bg);
  font-size: 13px;
}

.card .grow {
  flex: 1;
}

.links {
  display: flex;
  gap: 16px;
}

.links .more {
  font-size: 14px;
}

.num {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border-radius: 50%;
  background: var(--vp-button-brand-bg);
  color: #fff;
  font-size: 14px;
  font-weight: 700;
}

.tour .container {
  gap: 72px;
}

.feature {
  display: flex;
  align-items: center;
  gap: 48px;
}

.feature.flip {
  flex-direction: row-reverse;
}

.feature .text {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.feature .media {
  flex: none;
  width: 500px;
}

.kicker-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}

.kicker {
  color: var(--vp-c-brand-1);
  font-size: 12.5px;
  font-weight: 650;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

.badge {
  display: inline-flex;
  align-items: center;
  height: 22px;
  padding: 0 8px;
  border-radius: 6px;
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-brand-1);
  font-size: 12px;
  font-weight: 600;
}

.extras {
  gap: 14px;
}

.extra {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 16px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  color: var(--vp-c-text-2);
  font-size: 13.5px;
  line-height: 1.5;
  text-decoration: none;
  transition: border-color 0.2s;
}

.extra:hover {
  border-color: var(--vp-c-brand-1);
}

.extra b {
  color: var(--vp-c-text-1);
  font-size: 15px;
}

.stat {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 22px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 14px;
  background: var(--vp-c-bg);
}

.stat b {
  font-size: 40px;
  letter-spacing: -0.02em;
}

.stat .body {
  font-size: 14.5px;
}

.privacy {
  flex-direction: row;
  align-items: flex-start;
  gap: 56px;
}

.privacy-title {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 12px;
  color: var(--vp-c-brand-1);
}

.privacy-title h2 {
  color: var(--vp-c-text-1);
}

.checks {
  flex: 1.2;
  display: flex;
  flex-direction: column;
  gap: 14px;
  margin: 0;
  padding: 6px 0 0;
  list-style: none;
}

.checks li {
  position: relative;
  padding-left: 26px;
  color: var(--vp-c-text-2);
  font-size: 15px;
  line-height: 1.55;
}

.checks li::before {
  content: '';
  position: absolute;
  left: 2px;
  top: 7px;
  width: 12px;
  height: 7px;
  border-left: 2px solid var(--vp-c-brand-1);
  border-bottom: 2px solid var(--vp-c-brand-1);
  transform: rotate(-45deg);
}

.closing {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 18px;
  padding: 80px var(--gutter) 96px;
  text-align: center;
}

.closing .meta a {
  color: var(--vp-c-brand-1);
}

@media (max-width: 960px) {
  .feature,
  .feature.flip {
    flex-direction: column;
    align-items: stretch;
    gap: 20px;
  }

  .feature .media {
    width: 100%;
    order: -1;
  }

  .privacy {
    flex-direction: column;
    gap: 24px;
  }
}

@media (max-width: 720px) {
  .grid.three {
    grid-template-columns: minmax(0, 1fr);
  }

  .hero {
    padding-top: 36px;
  }

  .hero h1 {
    font-size: 36px;
  }

  .lead {
    font-size: 16.5px;
  }

  .actions {
    flex-direction: column;
    align-self: stretch;
  }

  .container {
    padding-top: 56px;
    padding-bottom: 56px;
  }

  .steps .container {
    padding-top: 80px;
  }

  section h2 {
    font-size: 25px;
  }

  .tour .container {
    gap: 48px;
  }
}
</style>
