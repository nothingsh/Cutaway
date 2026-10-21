<script setup lang="ts">
// The home page, for someone who has just heard of Cutaway: what it is, how to start, what it
// does, and why it can be trusted. Follows the canvas board "Website (proposal)". The text is in
// home.ts, one table per language.
import { useData, withBase } from 'vitepress'
import PartsDiagram from './PartsDiagram.vue'
import Loop from './Loop.vue'
import text from '../home'
import { useLocale } from '../locale'

const { theme } = useData()
const cutaway = theme.value.cutaway as { version: string; download: string; releases: string }
const { t, link } = useLocale(text)
</script>

<template>
  <div class="home">
    <section class="hero">
      <a class="pill" :href="link('/resources/releases')"><b>{{ t.pill[0] }}</b>{{ t.pill[1] }}</a>
      <h1>{{ t.title }}</h1>
      <p class="lead">{{ t.lead }}</p>
      <div class="actions">
        <a class="button primary" :href="cutaway.download">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M8 2v9M4 7.5 L8 11.5 L12 7.5M3 14h10" /></svg>
          {{ t.download }}
        </a>
        <a class="button secondary" :href="link('/guide/getting-started')">{{ t.start }}</a>
      </div>
      <p class="meta">{{ t.meta(cutaway.version) }}</p>
      <div class="product">
        <img class="light-only" :src="withBase('/media/home-overview-light.png')" width="1600" height="1000" fetchpriority="high" :alt="t.overview" />
        <img class="dark-only" :src="withBase('/media/home-overview-dark.png')" width="1600" height="1000" :alt="t.overview" />
      </div>
    </section>

    <section class="band steps">
      <div class="container">
        <header class="center">
          <h2>{{ t.steps.title }}</h2>
          <p class="body">{{ t.steps.text }}</p>
        </header>
        <div class="grid three">
          <div v-for="(step, index) in t.steps.items" :key="index" class="card">
            <span class="num">{{ index + 1 }}</span>
            <h3>{{ step.title }}</h3>
            <p class="body">{{ step.text }}</p>
            <pre v-if="index === 0"><code>CutawayServer.start()</code></pre>
          </div>
        </div>
        <a class="more center-self" :href="link('/guide/getting-started')">{{ t.steps.more }}</a>
      </div>
    </section>

    <section class="tour">
      <div class="container">
        <header class="center">
          <h2>{{ t.tour.title }}</h2>
          <p class="body narrow">{{ t.tour.text }}</p>
        </header>
        <div v-for="(feature, index) in t.features" :key="feature.video" class="feature" :class="{ flip: index % 2 === 1 }">
          <div class="text">
            <div class="kicker-row">
              <span class="kicker">{{ feature.kicker }}</span>
              <span v-if="feature.badge" class="badge">{{ feature.badge }}</span>
            </div>
            <h3>{{ feature.title }}</h3>
            <p class="body">{{ feature.text }}</p>
            <a class="more" :href="link(feature.link)">{{ feature.more }} →</a>
          </div>
          <Loop class="media" :name="feature.video" :alt="feature.alt" />
        </div>
        <div class="grid three extras">
          <a v-for="extra in t.extras" :key="extra.link" class="extra" :href="link(extra.link)">
            <b>{{ extra.title }}</b>
            <span>{{ extra.text }}</span>
          </a>
        </div>
      </div>
    </section>

    <section class="band">
      <div class="container">
        <header>
          <h2>{{ t.speed.title }}</h2>
          <p class="body narrow">{{ t.speed.text }}</p>
        </header>
        <div class="grid three">
          <div v-for="stat in t.speed.stats" :key="stat.value" class="stat">
            <b>{{ stat.value }}</b>
            <span class="body">{{ stat.text }}</span>
          </div>
        </div>
        <a class="more" :href="link('/resources/performance')">{{ t.speed.more }}</a>
      </div>
    </section>

    <section>
      <div class="container privacy">
        <div class="privacy-title">
          <svg width="36" height="36" viewBox="0 0 36 36" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="7" y="15" width="22" height="16" rx="4" /><path d="M12 15v-4a6 6 0 0 1 12 0v4" /></svg>
          <h2>{{ t.privacy.title }}</h2>
          <a class="more" :href="link('/resources/privacy')">{{ t.privacy.more }}</a>
        </div>
        <ul class="checks">
          <li v-for="point in t.privacy.points" :key="point">{{ point }}</li>
        </ul>
      </div>
    </section>

    <section class="band">
      <div class="container">
        <header class="center">
          <h2>{{ t.parts.title }}</h2>
          <p class="body narrow">{{ t.parts.text }}</p>
        </header>
        <PartsDiagram />
        <div class="grid three">
          <div v-for="part in t.parts.items" :key="part.title" class="card">
            <h3>{{ part.title }}</h3>
            <p class="body grow">{{ part.text }}</p>
            <p class="meta">{{ part.meta }}</p>
            <div class="links">
              <a v-for="item in part.links" :key="item.text" class="more" :href="item.link ? link(item.link) : item.href">{{ item.text }} →</a>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section class="closing">
      <h2>{{ t.closing.title }}</h2>
      <div class="actions">
        <a class="button primary" :href="cutaway.download">{{ t.download }}</a>
        <a class="button secondary" :href="link('/guide/getting-started')">{{ t.start }}</a>
      </div>
      <p class="meta"><a :href="cutaway.releases">{{ t.closing.releases }}</a></p>
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
