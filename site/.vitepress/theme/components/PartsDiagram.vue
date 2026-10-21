<script setup lang="ts">
// How the three parts fit together: Cutaway on the Mac, the protocol between, CutawayServer
// inside the app. Laid out in a row, and in a column on a narrow screen.
import { useLocale } from '../locale'

const { t } = useLocale({
  en: {
    label:
      'Cutaway on your Mac talks to CutawayServer inside your app over the Cutaway Protocol: TCP over the loopback address for the Simulator, or over USB through usbmuxd for a device.',
    mac: 'on your Mac',
    transport: ['TCP over the loopback address,', 'or USB through usbmuxd'],
    app: 'Your app',
    where: 'Simulator or USB device'
  },
  'zh-Hans': {
    label:
      'Mac 上的 Cutaway 经 Cutaway Protocol 与你的 App 里的 CutawayServer 通信：模拟器经回环地址上的 TCP，设备经 usbmuxd 走 USB。',
    mac: '在你的 Mac 上',
    transport: ['回环地址上的 TCP，', '或经 usbmuxd 走 USB'],
    app: '你的 App',
    where: '模拟器或 USB 连接的设备'
  }
})
</script>

<template>
  <figure class="parts" role="img" :aria-label="t.label">
    <div class="node">
      <svg width="34" height="26" viewBox="0 0 34 26" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="5" y="2" width="24" height="16" rx="2" /><path d="M1 22h32" /></svg>
      <b>Cutaway</b>
      <span>{{ t.mac }}</span>
    </div>
    <div class="link">
      <span class="chip">Cutaway Protocol</span>
      <div class="line"></div>
      <span class="note">{{ t.transport[0] }}<br />{{ t.transport[1] }}</span>
    </div>
    <div class="node">
      <svg width="20" height="30" viewBox="0 0 20 30" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="2" y="1" width="16" height="28" rx="4" /><path d="M8 25h4" /></svg>
      <b>{{ t.app }}</b>
      <span class="chip">CutawayServer</span>
      <span>{{ t.where }}</span>
    </div>
  </figure>
</template>

<style scoped>
.parts {
  display: flex;
  align-items: center;
  justify-content: center;
  margin: 24px 0;
}

.node {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  min-width: 170px;
  padding: 16px 20px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 14px;
  background: var(--vp-c-bg);
  color: var(--vp-c-text-2);
  font-size: 13px;
  text-align: center;
}

.node b {
  color: var(--vp-c-text-1);
  font-size: 15px;
}

.link {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  width: 240px;
}

.line {
  width: 100%;
  height: 2px;
  background: var(--vp-c-brand-1);
  opacity: 0.55;
}

.note {
  color: var(--vp-c-text-3);
  font-size: 12.5px;
  line-height: 1.4;
  text-align: center;
}

.chip {
  display: inline-flex;
  align-items: center;
  height: 26px;
  padding: 0 10px;
  border-radius: 7px;
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-brand-1);
  font-size: 12.5px;
  font-weight: 650;
}

@media (max-width: 640px) {
  .parts {
    flex-direction: column;
  }

  .link {
    width: auto;
    padding: 10px 0;
  }

  .line {
    width: 2px;
    height: 40px;
  }
}
</style>
