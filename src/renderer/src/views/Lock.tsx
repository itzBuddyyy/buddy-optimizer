import { motion, useAnimationControls } from 'motion/react'
import { useEffect, useRef, useState } from 'react'
import { ArrowRight, Loader2 } from 'lucide-react'
import { api } from '@/lib/api'
import { spring } from '@/lib/motion'
import { useSettings } from '@/lib/store'
import { useT } from '@/i18n'
import logo from '@/assets/icon.svg'

export function Lock({ onUnlock }: { onUnlock: () => void }) {
  const t = useT()
  const { settings } = useSettings()
  const [pw, setPw] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [wait, setWait] = useState(0)
  const [caps, setCaps] = useState(false)
  const [now, setNow] = useState(new Date())
  const shake = useAnimationControls()
  const input = useRef<HTMLInputElement>(null)

  useEffect(() => { const id = setInterval(() => setNow(new Date()), 1000); return () => clearInterval(id) }, [])
  useEffect(() => { input.current?.focus() }, [])
  useEffect(() => {
    if (wait <= 0) return
    const id = setInterval(() => setWait((w) => Math.max(0, w - 1)), 1000)
    return () => clearInterval(id)
  }, [wait])

  async function submit() {
    if (!pw || busy || wait > 0) return
    setBusy(true)
    const r = await api.auth.unlock(pw)
    setBusy(false)
    if (r.ok) { onUnlock(); return }
    setPw('')
    if (r.waitMs) { setWait(Math.ceil(r.waitMs / 1000)); setError(null) } else setError(t('lock.wrong'))
    // the macOS login "no" shake: quick, damped, horizontal
    shake.start({ x: [0, -14, 12, -9, 6, -3, 0], transition: { duration: 0.5, ease: 'easeOut' } })
    input.current?.focus()
  }

  const locale = { en: 'en-US', it: 'it-IT', es: 'es-ES', fr: 'fr-FR', de: 'de-DE' }[settings.language]
  const time = now.toLocaleTimeString(locale, { hour: 'numeric', minute: '2-digit' })
  const date = now.toLocaleDateString(locale, { weekday: 'long', day: 'numeric', month: 'long' })

  return (
    <motion.div className="lock" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, scale: 1.04, filter: 'blur(12px)', transition: { duration: 0.42, ease: [0.4, 0, 0.2, 1] } }}>
      <motion.div className="lock-clock" initial={{ opacity: 0, y: -18 }} animate={{ opacity: 1, y: 0 }} transition={{ ...spring.gentle, delay: 0.05 }}>
        <div className="date">{date}</div>
        <div className="time num">{time}</div>
      </motion.div>

      <motion.div className="lock-card glass strong rim" initial={{ opacity: 0, y: 26, scale: 0.97 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ ...spring.smooth, delay: 0.12 }}>
        <motion.img src={logo} alt="" className="lock-logo" draggable={false}
          initial={{ scale: 0.6, rotate: -8, opacity: 0 }} animate={{ scale: 1, rotate: 0, opacity: 1 }} transition={{ ...spring.bouncy, delay: 0.2 }} />
        <h2>Buddy Optimizer</h2>
        <p>{t('lock.subtitle')}</p>
        <motion.form animate={shake} onSubmit={(e) => { e.preventDefault(); submit() }} className="lock-form">
          <input
            ref={input}
            className="input lock-input"
            type="password"
            autoComplete="current-password"
            placeholder={t('lock.placeholder')}
            value={pw}
            disabled={wait > 0}
            onChange={(e) => { setPw(e.target.value); setError(null) }}
            onKeyDown={(e) => setCaps(e.getModifierState('CapsLock'))}
            onKeyUp={(e) => setCaps(e.getModifierState('CapsLock'))}
            aria-label={t('lock.placeholder')}
          />
          <motion.button type="submit" className="lock-go" disabled={!pw || busy || wait > 0} aria-label={t('lock.unlock')}
            whileTap={{ scale: 0.9 }} animate={{ opacity: pw ? 1 : 0.35, scale: pw ? 1 : 0.92 }} transition={spring.snappy}>
            {busy ? <Loader2 size={17} className="spin" /> : <ArrowRight size={17} strokeWidth={2.4} />}
          </motion.button>
        </motion.form>
        <div className="lock-msg">
          {wait > 0 ? <span className="warn">{t('lock.wait', { s: wait })}</span>
            : error ? <span className="bad">{error}</span>
            : caps ? <span className="faint">{t('lock.caps')}</span>
            : <span>&nbsp;</span>}
        </div>
      </motion.div>
    </motion.div>
  )
}
