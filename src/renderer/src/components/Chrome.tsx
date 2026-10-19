import { motion } from 'motion/react'
import { useEffect, useState } from 'react'
import { Gauge, Lock, Minus, Settings as Cog, Sparkles, Square, X, Copy } from 'lucide-react'
import { api } from '@/lib/api'
import { useSettings } from '@/lib/store'
import { spring } from '@/lib/motion'
import { useT, type TKey } from '@/i18n'
import logo from '@/assets/icon.svg'

export function Backdrop() {
  return (
    <div className="backdrop" aria-hidden>
      <div className="field f1" />
      <div className="field f2" />
      <div className="field f3" />
      <div className="grain" />
    </div>
  )
}

export function TitleBar({ title }: { title?: string }) {
  const { settings } = useSettings()
  const [max, setMax] = useState(false)
  useEffect(() => api.win.onMaximized(setMax), [])
  const mac = settings.windowControls === 'mac'
  return (
    <header className="titlebar">
      {mac && (
        <div className="lights">
          <button className="close" aria-label="Close" onClick={() => api.win.close()}><X size={8} strokeWidth={3} /></button>
          <button className="min" aria-label="Minimize" onClick={() => api.win.minimize()}><Minus size={8} strokeWidth={3} /></button>
          <button className="max" aria-label="Maximize" onClick={() => api.win.maximize()}><Square size={6} strokeWidth={3} /></button>
        </div>
      )}
      {title && <div className="title">{title}</div>}
      <div className="spacer" />
      {!mac && (
        <div className="caption">
          <button aria-label="Minimize" onClick={() => api.win.minimize()}><Minus size={15} strokeWidth={1.5} /></button>
          <button aria-label="Maximize" onClick={() => api.win.maximize()}>{max ? <Copy size={12} strokeWidth={1.5} /> : <Square size={12} strokeWidth={1.5} />}</button>
          <button className="close" aria-label="Close" onClick={() => api.win.close()}><X size={16} strokeWidth={1.5} /></button>
        </div>
      )}
    </header>
  )
}

export type View = 'dashboard' | 'optimize' | 'settings'

const items: { id: View; icon: typeof Gauge; label: TKey }[] = [
  { id: 'dashboard', icon: Gauge, label: 'nav.dashboard' },
  { id: 'optimize', icon: Sparkles, label: 'nav.optimize' },
  { id: 'settings', icon: Cog, label: 'nav.settings' }
]

export function Sidebar({ view, onView, engineOn, reboot }: { view: View; onView: (v: View) => void; engineOn: boolean; reboot: boolean }) {
  const t = useT()
  return (
    <nav className="sidebar glass rim">
      <div className="brand">
        <img src={logo} alt="" draggable={false} />
        <div>
          <div className="name">Buddy Optimizer</div>
          <div className="sub">Purple Void Edition</div>
        </div>
      </div>
      {items.map((it) => {
        const Icon = it.icon
        const on = view === it.id
        return (
          <button key={it.id} className={`nav-item ${on ? 'active' : ''}`} onClick={() => onView(it.id)} aria-current={on ? 'page' : undefined}>
            {on && <motion.span layoutId="nav-pill" className="pill" transition={spring.snappy} />}
            <Icon size={18} strokeWidth={on ? 2.2 : 1.9} />
            <span>{t(it.label)}</span>
          </button>
        )
      })}
      <div className="grow" />
      <div className="foot">
        {reboot && (
          <div className="status-chip"><span className="dot warn" />{t('status.rebootPending')}</div>
        )}
        <div className="status-chip"><span className={`dot ${engineOn ? 'on' : ''}`} />{engineOn ? t('status.engineOn') : t('status.engineOff')}</div>
        <button className="nav-item" onClick={() => api.auth.lock()}>
          <Lock size={17} strokeWidth={1.9} />
          <span>{t('nav.lock')}</span>
        </button>
      </div>
    </nav>
  )
}
