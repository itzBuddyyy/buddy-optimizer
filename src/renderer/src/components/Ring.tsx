import { motion } from 'motion/react'
import { useId } from 'react'
import { spring } from '@/lib/motion'

interface Props {
  value: number          // 0-100
  size?: number
  stroke?: number
  children?: React.ReactNode
  tone?: 'accent' | 'ok' | 'warn' | 'bad'
}

const tones = {
  accent: ['#7c4dff', '#c78cff', '#ef8fd8'],
  ok: ['#3ccf91', '#5fe0a5', '#9af0c9'],
  warn: ['#ff9f43', '#ffc56b', '#ffe0a3'],
  bad: ['#ff4f74', '#ff6b8a', '#ffa3b8']
}

/** Activity-ring style gauge with a conic gradient sweep and soft glow. */
export function Ring({ value, size = 112, stroke = 10, children, tone = 'accent' }: Props) {
  const id = useId().replace(/:/g, '')
  const r = (size - stroke) / 2
  const c = 2 * Math.PI * r
  const v = Math.max(0, Math.min(100, value || 0))
  const colors = tones[tone]
  return (
    <div style={{ position: 'relative', width: size, height: size, flex: 'none' }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: 'rotate(-90deg)', overflow: 'visible' }}>
        <defs>
          <linearGradient id={`g${id}`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor={colors[0]} />
            <stop offset="55%" stopColor={colors[1]} />
            <stop offset="100%" stopColor={colors[2]} />
          </linearGradient>
          <filter id={`f${id}`} x="-30%" y="-30%" width="160%" height="160%">
            <feGaussianBlur stdDeviation="3.2" />
          </filter>
        </defs>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="currentColor" strokeOpacity={0.08} strokeWidth={stroke} />
        {/* glow copy underneath */}
        <motion.circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={`url(#g${id})`} strokeWidth={stroke} strokeLinecap="round"
          strokeDasharray={c} initial={false} animate={{ strokeDashoffset: c * (1 - v / 100) }} transition={spring.gentle}
          filter={`url(#f${id})`} opacity={0.55} />
        <motion.circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={`url(#g${id})`} strokeWidth={stroke} strokeLinecap="round"
          strokeDasharray={c} initial={false} animate={{ strokeDashoffset: c * (1 - v / 100) }} transition={spring.gentle} />
      </svg>
      <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', textAlign: 'center' }}>{children}</div>
    </div>
  )
}
