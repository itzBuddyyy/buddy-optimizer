import { resolve } from 'node:path'
import { defineConfig } from 'electron-vite'
import type { Plugin } from 'vite'
import react from '@vitejs/plugin-react'

// Strict CSP baked into the production index.html: only the app's own
// scripts, no remote code, no eval. (Inline *styles* are needed for animations.)
const CSP = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'none'"
const cspPlugin = (): Plugin => ({
  name: 'buddy-csp',
  apply: 'build',
  transformIndexHtml: (html) => html.replace('<head>', `<head>\n    <meta http-equiv="Content-Security-Policy" content="${CSP}" />`)
})

export default defineConfig({
  main: {
    build: { outDir: 'out/main' },
    resolve: { alias: { '@shared': resolve('src/shared'), '@winutil': resolve('engine/winutil') } }
  },
  preload: {
    build: { outDir: 'out/preload' },
    resolve: { alias: { '@shared': resolve('src/shared') } }
  },
  renderer: {
    root: 'src/renderer',
    build: { outDir: 'out/renderer' },
    resolve: { alias: { '@shared': resolve('src/shared'), '@winutil': resolve('engine/winutil'), '@': resolve('src/renderer/src') } },
    plugins: [react(), cspPlugin()]
  }
})
