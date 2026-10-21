// Lists the screenshots and videos in public/media at build time, so that a page shows a
// labelled placeholder for one that has not been made yet (see public/media/README.md).
import { basename } from 'node:path'
import { defineLoader } from 'vitepress'
import { readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const folder = fileURLToPath(new URL('../../public/media', import.meta.url))

export interface Data {
  files: string[]
}

declare const data: Data
export { data }

export default defineLoader({
  watch: ['../../public/media/*'],
  load(): Data {
    return { files: readdirSync(folder).filter((name) => !name.startsWith('.')).map((name) => basename(name)) }
  }
})
