// The site's languages. Pages are translated as files under zh-Hans/; a component keeps its own
// text for each language and picks it by the page's language. Images and videos are the same in
// every language: only text is translated.
import { computed } from 'vue'
import { useData, withBase } from 'vitepress'

export type Language = 'en' | 'zh-Hans'

export function useLocale<Text>(text: Record<Language, Text>) {
  const { lang, localeIndex } = useData()
  const language = computed<Language>(() => (lang.value === 'zh-Hans' ? 'zh-Hans' : 'en'))
  return {
    t: computed(() => text[language.value]),
    // A path of the English site, such as /guide/preview, in the page's language.
    link: (path: string) => withBase(localeIndex.value === 'root' ? path : `/${localeIndex.value}${path}`)
  }
}
