import { useEffect, useRef } from 'react'
import { animate, useMotionValue } from 'motion/react'

/** Counts smoothly to the new value (like the iOS Health / Activity numbers). */
export function AnimatedNumber({ value, digits = 0, suffix = '', className }: { value: number | null | undefined; digits?: number; suffix?: string; className?: string }) {
  const mv = useMotionValue(value ?? 0)
  const ref = useRef<HTMLSpanElement>(null)
  useEffect(() => {
    const unsub = mv.on('change', (v) => { if (ref.current) ref.current.textContent = v.toFixed(digits) + suffix })
    return unsub
  }, [mv, digits, suffix])
  useEffect(() => {
    if (value == null || !isFinite(value)) { if (ref.current) ref.current.textContent = '—'; return }
    const reduced = document.documentElement.dataset.motion !== 'full'
    const c = animate(mv, value, reduced ? { duration: 0 } : { type: 'spring', stiffness: 120, damping: 22 })
    return () => c.stop()
  }, [value, mv])
  return <span ref={ref} className={'num ' + (className ?? '')}>{value == null ? '—' : (value).toFixed(digits) + suffix}</span>
}
