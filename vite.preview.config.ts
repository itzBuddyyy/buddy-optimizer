// Browser-only preview of the interface (simulated data, no Electron):
//   npx vite --config vite.preview.config.ts
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const here = dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  root: resolve(here, 'src/renderer'),
  resolve: { alias: { '@shared': resolve(here, 'src/shared'), '@winutil': resolve(here, 'engine/winutil'), '@': resolve(here, 'src/renderer/src') } },
  plugins: [react()],
  server: { port: 5199, strictPort: true }
})
