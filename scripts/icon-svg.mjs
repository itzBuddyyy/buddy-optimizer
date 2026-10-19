// Generates the Buddy Optimizer icon as pure vector geometry (no raster, no AI).
// Concept: a performance gauge inside a macOS-style squircle made of "Purple
// Void" glass. The lit part of the arc runs from idle to ~80% - "tuned".
//
//   node scripts/icon-svg.mjs   -> src/renderer/src/assets/icon.svg   (master, 1024 px)
//                                  build/icon-small.svg               (16-48 px variant:
//                                  no ticks, heavier strokes so it stays legible)
//
// The squircle is a true superellipse (n = 5), the shape Apple's icon grid
// approximates, sampled finely so it stays smooth at 1024 px.

import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const S = 1024            // canvas
const C = S / 2

function squircle(size, n = 5, cx = C, cy = C, steps = 720) {
  const a = size / 2
  const pts = []
  for (let i = 0; i < steps; i++) {
    const t = (i / steps) * Math.PI * 2
    const ct = Math.cos(t), st = Math.sin(t)
    const x = cx + a * Math.sign(ct) * Math.pow(Math.abs(ct), 2 / n)
    const y = cy + a * Math.sign(st) * Math.pow(Math.abs(st), 2 / n)
    pts.push(`${x.toFixed(2)},${y.toFixed(2)}`)
  }
  return `M${pts[0]}L${pts.slice(1).join('L')}Z`
}

function build(small) {
  const B = small ? 900 : 824        // small sizes use more of the canvas
  const R = small ? 290 : 268        // arc radius
  const GY = C + (small ? 40 : 34)   // gauge centre slightly low (optical centre)
  const W = small ? 92 : 46          // arc stroke
  const START = 135, SWEEP = 270
  const LEVEL = 0.80
  const polar = (deg, r = R) => [C + r * Math.cos((deg * Math.PI) / 180), GY + r * Math.sin((deg * Math.PI) / 180)]
  const arc = (from, to, r = R) => {
    const [x1, y1] = polar(from, r), [x2, y2] = polar(to, r)
    return `M${x1.toFixed(2)},${y1.toFixed(2)}A${r},${r} 0 ${to - from > 180 ? 1 : 0} 1 ${x2.toFixed(2)},${y2.toFixed(2)}`
  }
  const needleDeg = START + SWEEP * LEVEL
  const [tipX, tipY] = polar(needleDeg, small ? R - 70 : R - 44)
  const hubR = small ? 74 : 48

  let ticks = ''
  if (!small) {
    for (let i = 0; i <= 10; i++) {
      const d = START + (SWEEP / 10) * i
      const [x1, y1] = polar(d, R - 58)
      const [x2, y2] = polar(d, R - (i % 5 === 0 ? 86 : 74))
      const lit = i / 10 <= LEVEL
      ticks += `<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" stroke="#fff" stroke-opacity="${lit ? 0.55 : 0.18}" stroke-width="${i % 5 === 0 ? 10 : 7}" stroke-linecap="round"/>`
    }
  }

  // tapered needle
  const ang = (needleDeg * Math.PI) / 180
  const nx = -Math.sin(ang), ny = Math.cos(ang)
  const base = small ? 34 : 19, tip = small ? 14 : 7
  const b1 = [C + nx * base, GY + ny * base], b2 = [C - nx * base, GY - ny * base]
  const t1 = [tipX + nx * tip, tipY + ny * tip], t2 = [tipX - nx * tip, tipY - ny * tip]
  const f = (p) => p.map((v) => v.toFixed(1)).join(',')
  const needle = `M${f(b1)}L${f(t1)}A${tip},${tip} 0 0 0 ${f(t2)}L${f(b2)}Z`

  const body = squircle(B)
  const inner = squircle(B - 6)

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
  <defs>
    <linearGradient id="bodyGrad" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="#53287d"/>
      <stop offset="0.42" stop-color="#2a1342"/>
      <stop offset="1" stop-color="#0c0415"/>
    </linearGradient>
    <radialGradient id="voidGlow" cx="0.5" cy="0.62" r="0.55">
      <stop offset="0" stop-color="#8b4dff" stop-opacity="0.6"/>
      <stop offset="0.45" stop-color="#6a2fd6" stop-opacity="0.22"/>
      <stop offset="1" stop-color="#442244" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="rimLight" cx="0.28" cy="0.08" r="0.9">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/>
      <stop offset="0.5" stop-color="#ffffff" stop-opacity="0.03"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/>
      <stop offset="0.48" stop-color="#ffffff" stop-opacity="0.02"/>
      <stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="arcGrad" gradientUnits="userSpaceOnUse" x1="${polar(START)[0].toFixed(1)}" y1="${polar(START)[1].toFixed(1)}" x2="${polar(START + SWEEP)[0].toFixed(1)}" y2="${(polar(START + SWEEP)[1] - 120).toFixed(1)}">
      <stop offset="0" stop-color="#6d3cff"/>
      <stop offset="0.55" stop-color="#b56cff"/>
      <stop offset="1" stop-color="#ffc6ef"/>
    </linearGradient>
    <linearGradient id="needleGrad" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset="1" stop-color="#f2d6ff"/>
    </linearGradient>
    <radialGradient id="hubGrad" cx="0.4" cy="0.35" r="0.7">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset="0.55" stop-color="#e9c8ff"/>
      <stop offset="1" stop-color="#a66bff"/>
    </radialGradient>
    <filter id="glow" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="${small ? 16 : 22}"/></filter>
    <filter id="softShadow" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="${small ? 10 : 18}" stdDeviation="${small ? 12 : 22}" flood-color="#09020f" flood-opacity="0.5"/></filter>
    <clipPath id="clip"><path d="${body}"/></clipPath>
  </defs>
  <g filter="url(#softShadow)"><path d="${body}" fill="url(#bodyGrad)"/></g>
  <g clip-path="url(#clip)">
    <rect width="${S}" height="${S}" fill="url(#voidGlow)"/>
    <rect width="${S}" height="${S}" fill="url(#rimLight)"/>
    ${small ? '' : `<circle cx="${C}" cy="${GY}" r="${R + 92}" fill="none" stroke="#fff" stroke-opacity="0.045" stroke-width="2"/>
    <circle cx="${C}" cy="${GY}" r="${R + 150}" fill="none" stroke="#fff" stroke-opacity="0.03" stroke-width="2"/>`}
  </g>
  <path d="${arc(START, START + SWEEP)}" fill="none" stroke="#ffffff" stroke-opacity="${small ? 0.16 : 0.10}" stroke-width="${W}" stroke-linecap="round"/>
  <path d="${arc(START, needleDeg)}" fill="none" stroke="url(#arcGrad)" stroke-width="${W}" stroke-linecap="round" filter="url(#glow)" opacity="0.85"/>
  <path d="${arc(START, needleDeg)}" fill="none" stroke="url(#arcGrad)" stroke-width="${W}" stroke-linecap="round"/>
  ${small ? '' : `<path d="${arc(START + 6, needleDeg - 4, R + 14)}" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="5" stroke-linecap="round"/>`}
  ${ticks}
  <line x1="${C}" y1="${GY}" x2="${tipX.toFixed(1)}" y2="${tipY.toFixed(1)}" stroke="#d9a8ff" stroke-width="${small ? 50 : 32}" stroke-linecap="round" filter="url(#glow)" opacity="0.7"/>
  <path d="${needle}" fill="url(#needleGrad)"/>
  <circle cx="${C}" cy="${GY}" r="${hubR}" fill="url(#hubGrad)"/>
  <circle cx="${C}" cy="${GY}" r="${hubR}" fill="none" stroke="#ffffff" stroke-opacity="0.6" stroke-width="3"/>
  <circle cx="${C}" cy="${GY}" r="${small ? 24 : 16}" fill="#3a1960"/>
  <path d="${body}" fill="url(#sheen)"/>
  <path d="${inner}" fill="none" stroke="#ffffff" stroke-opacity="0.10" stroke-width="3"/>
</svg>
`
}

const master = resolve(root, 'src/renderer/src/assets/icon.svg')
const small = resolve(root, 'build/icon-small.svg')
mkdirSync(dirname(master), { recursive: true })
mkdirSync(dirname(small), { recursive: true })
writeFileSync(master, build(false))
writeFileSync(small, build(true))
console.log('icon.svg + icon-small.svg written')
