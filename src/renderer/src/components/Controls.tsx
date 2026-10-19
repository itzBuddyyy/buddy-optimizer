import { motion, AnimatePresence } from 'motion/react'
import { useEffect, useId, useRef, useState, type ReactNode } from 'react'
import { Check, ChevronDown } from 'lucide-react'
import { spring } from '@/lib/motion'

// ------------------------------------------------------------------ Switch (iOS style)

export function Switch({ checked, onChange, disabled }: { checked: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className="switch"
      data-on={checked}
      style={{ opacity: disabled ? 0.4 : 1 }}
    >
      <motion.span className="knob" layout transition={spring.snappy} whileTap={{ width: 26 }} />
    </button>
  )
}

// ------------------------------------------------------------------ Segmented control

export function Segmented<T extends string | number>({ value, options, onChange, size = 'md' }: { value: T; options: { value: T; label: ReactNode }[]; onChange: (v: T) => void; size?: 'sm' | 'md' }) {
  const id = useId()
  return (
    <div className={`segmented ${size}`} role="radiogroup">
      {options.map((o) => (
        <button key={String(o.value)} role="radio" aria-checked={o.value === value} className={o.value === value ? 'on' : ''} onClick={() => onChange(o.value)}>
          {o.value === value && <motion.span layoutId={`seg-${id}`} className="seg-thumb" transition={spring.snappy} />}
          <span className="seg-label">{o.label}</span>
        </button>
      ))}
    </div>
  )
}

// ------------------------------------------------------------------ Slider

export function Slider({ value, min, max, step = 1, onChange, format }: { value: number; min: number; max: number; step?: number; onChange: (v: number) => void; format?: (v: number) => string }) {
  const [local, setLocal] = useState(value)
  useEffect(() => setLocal(value), [value])
  const pct = ((local - min) / (max - min)) * 100
  return (
    <div className="slider">
      <input
        type="range" min={min} max={max} step={step} value={local}
        onChange={(e) => setLocal(Number(e.target.value))}
        onPointerUp={() => onChange(local)}
        onKeyUp={() => onChange(local)}
        style={{ ['--p' as string]: `${pct}%` }}
      />
      <span className="slider-val num">{format ? format(local) : local}</span>
    </div>
  )
}

// ------------------------------------------------------------------ Select (popover menu)

export function Select<T extends string | number>({ value, options, onChange, width = 200 }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void; width?: number }) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!open) return
    const close = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setOpen(false) }
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false) }
    window.addEventListener('mousedown', close)
    window.addEventListener('keydown', esc)
    return () => { window.removeEventListener('mousedown', close); window.removeEventListener('keydown', esc) }
  }, [open])
  const current = options.find((o) => o.value === value)
  return (
    <div className="select" ref={ref} style={{ width }}>
      <button className="select-btn" onClick={() => setOpen((o) => !o)} aria-expanded={open}>
        <span>{current?.label}</span>
        <ChevronDown size={15} style={{ transition: 'transform var(--dur-2) var(--spring)', transform: open ? 'rotate(180deg)' : 'none' }} />
      </button>
      <AnimatePresence>
        {open && (
          <motion.div className="select-menu glass strong rim"
            initial={{ opacity: 0, y: -6, scale: 0.97, filter: 'blur(4px)' }}
            animate={{ opacity: 1, y: 0, scale: 1, filter: 'blur(0px)' }}
            exit={{ opacity: 0, y: -4, scale: 0.98, transition: { duration: 0.12 } }}
            transition={spring.snappy}>
            {options.map((o) => (
              <button key={String(o.value)} className={o.value === value ? 'on' : ''} onClick={() => { onChange(o.value); setOpen(false) }}>
                <span>{o.label}</span>
                {o.value === value && <Check size={15} />}
              </button>
            ))}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}

// ------------------------------------------------------------------ Checkbox

export function Checkbox({ checked, onChange, disabled }: { checked: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <button role="checkbox" aria-checked={checked} disabled={disabled} className="checkbox" data-on={checked} onClick={() => onChange(!checked)}>
      <AnimatePresence>
        {checked && (
          <motion.svg viewBox="0 0 16 16" width="12" height="12" initial={{ scale: 0.4, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} exit={{ scale: 0.4, opacity: 0 }} transition={spring.bouncy}>
            <motion.path d="M3.5 8.5l3 3 6-7" fill="none" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"
              initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.22, ease: [0.22, 1, 0.36, 1] }} />
          </motion.svg>
        )}
      </AnimatePresence>
    </button>
  )
}

// ------------------------------------------------------------------ Bar meter

export function Meter({ value, tone = 'accent', height = 6 }: { value: number; tone?: 'accent' | 'ok' | 'warn' | 'bad'; height?: number }) {
  const v = Math.max(0, Math.min(100, value || 0))
  return (
    <div className="meter" style={{ height }}>
      <motion.div className={`meter-fill ${tone}`} initial={false} animate={{ width: `${v}%` }} transition={spring.gentle} />
    </div>
  )
}
