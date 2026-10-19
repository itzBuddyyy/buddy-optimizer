// Renders every raster asset from the vector masters:
//   build/icon.ico            16-256 px (16-48 from the simplified small variant)
//   build/icon.png            512 px (Linux / store listings / README)
//   build/installerSidebar.bmp  164x314 NSIS welcome/finish artwork
//   build/installerHeader.bmp   150x57  NSIS page header
//   build/uninstallerSidebar.bmp
import { Resvg } from '@resvg/resvg-js'
import pngToIco from 'png-to-ico'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
execFileSync(process.execPath, [resolve(root, 'scripts/icon-svg.mjs')], { stdio: 'inherit' })

const master = readFileSync(resolve(root, 'src/renderer/src/assets/icon.svg'), 'utf8')
const small = readFileSync(resolve(root, 'build/icon-small.svg'), 'utf8')
const out = (f) => resolve(root, 'build', f)
mkdirSync(resolve(root, 'build'), { recursive: true })

const render = (svg, w, h) => new Resvg(svg, { fitTo: { mode: 'width', value: w }, font: { loadSystemFonts: true, defaultFontFamily: 'Segoe UI' } }).render()
const png = (svg, size) => render(svg, size).asPng()

// ---- icon.ico + icon.png
const sizes = [16, 24, 32, 48, 64, 128, 256]
const pngs = sizes.map((s) => png(s <= 48 ? small : master, s))
writeFileSync(out('icon.ico'), await pngToIco(pngs))
writeFileSync(out('icon.png'), png(master, 512))

// ---- 24-bit BMP encoder (NSIS needs BMP)
function bmp(rendered, bg = [11, 6, 18]) {
  const { width: w, height: h } = rendered
  const px = rendered.pixels               // RGBA, premultiplied? resvg gives straight RGBA
  const rowSize = Math.ceil((w * 3) / 4) * 4
  const size = 54 + rowSize * h
  const buf = Buffer.alloc(size)
  buf.write('BM', 0); buf.writeUInt32LE(size, 2); buf.writeUInt32LE(54, 10)
  buf.writeUInt32LE(40, 14); buf.writeInt32LE(w, 18); buf.writeInt32LE(h, 22)
  buf.writeUInt16LE(1, 26); buf.writeUInt16LE(24, 28); buf.writeUInt32LE(rowSize * h, 34)
  for (let y = 0; y < h; y++) {
    const row = 54 + (h - 1 - y) * rowSize          // bottom-up
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4
      const a = px[i + 3] / 255
      buf[row + x * 3 + 0] = Math.round(px[i + 2] * a + bg[2] * (1 - a))
      buf[row + x * 3 + 1] = Math.round(px[i + 1] * a + bg[1] * (1 - a))
      buf[row + x * 3 + 2] = Math.round(px[i + 0] * a + bg[0] * (1 - a))
    }
  }
  return buf
}

const iconData = 'data:image/png;base64,' + png(master, 256).toString('base64')

// ---- installer sidebar: vertical Purple Void panel, aurora light, icon, wordmark
const sidebar = (title, line2) => `<svg xmlns="http://www.w3.org/2000/svg" width="164" height="314" viewBox="0 0 164 314">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.6" y2="1">
      <stop offset="0" stop-color="#2d1547"/><stop offset="0.55" stop-color="#160a24"/><stop offset="1" stop-color="#07030c"/>
    </linearGradient>
    <radialGradient id="a1" cx="0.2" cy="0.18" r="0.7"><stop offset="0" stop-color="#7c4dff" stop-opacity="0.55"/><stop offset="1" stop-color="#7c4dff" stop-opacity="0"/></radialGradient>
    <radialGradient id="a2" cx="0.95" cy="0.75" r="0.6"><stop offset="0" stop-color="#d45fc1" stop-opacity="0.35"/><stop offset="1" stop-color="#d45fc1" stop-opacity="0"/></radialGradient>
    <linearGradient id="txt" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#e6c9ff"/></linearGradient>
  </defs>
  <rect width="164" height="314" fill="url(#bg)"/>
  <rect width="164" height="314" fill="url(#a1)"/>
  <rect width="164" height="314" fill="url(#a2)"/>
  <circle cx="82" cy="104" r="78" fill="none" stroke="#fff" stroke-opacity="0.05"/>
  <circle cx="82" cy="104" r="104" fill="none" stroke="#fff" stroke-opacity="0.035"/>
  <image href="${iconData}" x="34" y="56" width="96" height="96"/>
  <text x="82" y="190" text-anchor="middle" font-family="Segoe UI Variable Display, Segoe UI" font-weight="700" font-size="17" letter-spacing="-0.3" fill="url(#txt)">${title}</text>
  <text x="82" y="210" text-anchor="middle" font-family="Segoe UI Variable Text, Segoe UI" font-weight="500" font-size="10.5" fill="#ffffff" fill-opacity="0.55">${line2}</text>
  <rect x="62" y="226" width="40" height="2" rx="1" fill="#b56cff" fill-opacity="0.8"/>
</svg>`

writeFileSync(out('installerSidebar.bmp'), bmp(render(sidebar('Buddy Optimizer', 'Performance, tuned.'), 164)))
writeFileSync(out('uninstallerSidebar.bmp'), bmp(render(sidebar('Buddy Optimizer', 'See you soon.'), 164)))

const header = `<svg xmlns="http://www.w3.org/2000/svg" width="150" height="57" viewBox="0 0 150 57">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#f3ebff"/></linearGradient></defs>
  <rect width="150" height="57" fill="url(#bg)"/>
  <image href="${iconData}" x="104" y="8" width="41" height="41"/>
</svg>`
writeFileSync(out('installerHeader.bmp'), bmp(render(header, 150), [255, 255, 255]))

console.log('icons + installer artwork written to build/')
