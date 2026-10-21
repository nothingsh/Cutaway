// The default theme without its bundled web font (the site uses the system's fonts and loads
// nothing from elsewhere), with Cutaway's colors and the components the pages use.
import DefaultTheme from 'vitepress/theme-without-fonts'
import type { Theme } from 'vitepress'
import './custom.css'
import HomePage from './components/HomePage.vue'
import Shot from './components/Shot.vue'
import Loop from './components/Loop.vue'
import Shortcuts from './components/Shortcuts.vue'
import NextSteps from './components/NextSteps.vue'
import PartsDiagram from './components/PartsDiagram.vue'
import FrameDiagram from './components/FrameDiagram.vue'
import ExchangeDiagram from './components/ExchangeDiagram.vue'
import BuildsDiagram from './components/BuildsDiagram.vue'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('HomePage', HomePage)
    app.component('Shot', Shot)
    app.component('Loop', Loop)
    app.component('Shortcuts', Shortcuts)
    app.component('NextSteps', NextSteps)
    app.component('PartsDiagram', PartsDiagram)
    app.component('FrameDiagram', FrameDiagram)
    app.component('ExchangeDiagram', ExchangeDiagram)
    app.component('BuildsDiagram', BuildsDiagram)
  }
} satisfies Theme
