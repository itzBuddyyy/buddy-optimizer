import { useEffect, useRef } from 'react'

interface Props {
  data: number[]
  data2?: number[]          // optional second series (e.g. upload under download)
  max?: number              // fixed scale (e.g. 100 for %); auto when omitted
  height?: number
  color?: [string, string]  // gradient stops for the line
  color2?: [string, string]
  capacity?: number
  animate?: boolean
  version: number           // changes on every new sample (arrays are mutated in place)
}

/**
 * Canvas area chart. Draws at device-pixel resolution and eases between
 * samples at 60 fps, so new data glides in from the right instead of
 * jumping once per second.
 */
export function Sparkline({ data, data2, max, height = 64, color = ['#9a7bff', '#ef8fd8'], color2 = ['#5fe0a5', '#8ab4ff'], capacity = 90, animate = true, version }: Props) {
  const ref = useRef<HTMLCanvasElement>(null)
  const state = useRef({ shown: [] as number[], shown2: [] as number[], target: [] as number[], target2: [] as number[], scale: 1, raf: 0, shift: 0 })

  useEffect(() => {
    const s = state.current
    const fresh = s.target.length > 0
    s.target = data.slice(-capacity)
    s.target2 = (data2 ?? []).slice(-capacity)
    if (!fresh || !animate) { s.shown = [...s.target]; s.shown2 = [...s.target2] }
    else {
      // new sample arrived: drop the oldest shown point so the curve scrolls left
      if (s.shown.length >= capacity) s.shown.shift()
      if (s.shown2.length >= capacity) s.shown2.shift()
      s.shift = 1
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version, capacity, animate])

  useEffect(() => {
    const canvas = ref.current!
    const ctx = canvas.getContext('2d')!
    const s = state.current
    let alive = true

    const draw = () => {
      if (!alive) return
      const dpr = window.devicePixelRatio || 1
      const w = canvas.clientWidth
      const h = canvas.clientHeight
      if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
        canvas.width = Math.round(w * dpr)
        canvas.height = Math.round(h * dpr)
      }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      ctx.clearRect(0, 0, w, h)

      // ease values + scale towards targets
      const k = animate ? 0.18 : 1
      const align = (shown: number[], target: number[]) => {
        // new samples enter on the right, starting from the previous value so they ease in
        while (shown.length < target.length) shown.push(shown.length ? shown[shown.length - 1] : (target[0] ?? 0))
        while (shown.length > target.length) shown.shift()
        for (let i = 0; i < target.length; i++) shown[i] += (target[i] - shown[i]) * k
      }
      align(s.shown, s.target)
      align(s.shown2, s.target2)
      const peak = max ?? Math.max(1, ...s.target, ...s.target2) * 1.15
      s.scale += (peak - s.scale) * (animate ? 0.12 : 1)
      s.shift *= animate ? 0.86 : 0

      const step = w / (capacity - 1)
      const offset = s.shift * step

      const path = (vals: number[]) => {
        const pts = vals.map((v, i) => [w - (vals.length - 1 - i) * step + offset, h - 2 - (Math.max(0, v) / s.scale) * (h - 6)] as const)
        return pts
      }

      const stroke = (vals: number[], c: [string, string], fillAlpha: number) => {
        if (vals.length < 2) return
        const pts = path(vals)
        ctx.beginPath()
        ctx.moveTo(pts[0][0], pts[0][1])
        // Catmull-Rom -> bezier for a smooth, honest curve (no overshoot below 0)
        for (let i = 0; i < pts.length - 1; i++) {
          const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(pts.length - 1, i + 2)]
          const t = 0.18
          ctx.bezierCurveTo(p1[0] + (p2[0] - p0[0]) * t, Math.min(h - 2, p1[1] + (p2[1] - p0[1]) * t), p2[0] - (p3[0] - p1[0]) * t, Math.min(h - 2, p2[1] - (p3[1] - p1[1]) * t), p2[0], p2[1])
        }
        const lg = ctx.createLinearGradient(0, 0, w, 0)
        lg.addColorStop(0, c[0]); lg.addColorStop(1, c[1])
        ctx.lineWidth = 1.8
        ctx.lineJoin = 'round'
        ctx.strokeStyle = lg
        ctx.stroke()
        // area fill
        ctx.lineTo(pts[pts.length - 1][0], h)
        ctx.lineTo(pts[0][0], h)
        ctx.closePath()
        const fg = ctx.createLinearGradient(0, 0, 0, h)
        fg.addColorStop(0, hexA(c[1], fillAlpha))
        fg.addColorStop(1, hexA(c[0], 0))
        ctx.fillStyle = fg
        ctx.fill()
        // live point
        const last = pts[pts.length - 1]
        ctx.beginPath()
        ctx.arc(last[0] - 1, last[1], 2.6, 0, Math.PI * 2)
        ctx.fillStyle = c[1]
        ctx.shadowColor = c[1]
        ctx.shadowBlur = 10
        ctx.fill()
        ctx.shadowBlur = 0
      }

      ctx.save()
      ctx.beginPath()
      ctx.rect(0, 0, w, h)
      ctx.clip()
      if (s.shown2.length) stroke(s.shown2, color2, 0.18)
      stroke(s.shown, color, 0.28)
      ctx.restore()
      s.raf = requestAnimationFrame(draw)
    }
    s.raf = requestAnimationFrame(draw)
    return () => { alive = false; cancelAnimationFrame(s.raf) }
  }, [max, capacity, animate, color, color2])

  return <canvas ref={ref} style={{ width: '100%', height, display: 'block' }} />
}

function hexA(hex: string, a: number) {
  const h = hex.replace('#', '')
  const n = parseInt(h.length === 3 ? h.split('').map((c) => c + c).join('') : h, 16)
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`
}
