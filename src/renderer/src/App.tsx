import { AnimatePresence, MotionConfig, motion } from 'motion/react'
import { useEffect, useRef, useState } from 'react'
import { api } from '@/lib/api'
import { useSettings } from '@/lib/store'
import { EngineProvider, useEngine } from '@/lib/engine'
import { OverlayProvider } from '@/components/Overlay'
import { Backdrop, Sidebar, TitleBar, type View } from '@/components/Chrome'
import { UpdateBanner } from '@/components/UpdateBanner'
import { Lock } from '@/views/Lock'
import { Dashboard } from '@/views/Dashboard'
import { Optimize } from '@/views/Optimize'
import { Games } from '@/views/Games'
import { Tweaks } from '@/views/Tweaks'
import { Apps } from '@/views/Apps'
import { SystemTools } from '@/views/SystemTools'
import { IsoCreator } from '@/views/IsoCreator'
import { SettingsView } from '@/views/Settings'
import { useT } from '@/i18n'

function Shell() {
  const t = useT()
  const eng = useEngine()
  const [view, setView] = useState<View>('dashboard')
  const contentRef = useRef<HTMLElement>(null)
  // each section starts at the top (like switching panes in System Settings)
  useEffect(() => { contentRef.current?.scrollTo({ top: 0 }) }, [view])
  const titles: Record<View, string> = { dashboard: t('nav.dashboard'), optimize: t('nav.optimize'), tweaks: t('nav.tweaks'), apps: t('nav.apps'), games: t('nav.games'), system: t('nav.system'), iso: t('nav.iso'), settings: t('nav.settings') }
  // keyboard: Ctrl+1..8 switch sections, Ctrl+L locks
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!e.ctrlKey) return
      if (e.key === '1') setView('dashboard')
      else if (e.key === '2') setView('optimize')
      else if (e.key === '3') setView('games')
      else if (e.key === '4' || e.key === ',') setView('settings')
      else if (e.key === '5') setView('tweaks')
      else if (e.key === '6') setView('apps')
      else if (e.key === '7') setView('system')
      else if (e.key === '8') setView('iso')
      else if (e.key.toLowerCase() === 'l') api.auth.lock()
      else return
      e.preventDefault()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])
  return (
    <motion.div className="app" initial={{ opacity: 0, scale: 0.985, filter: 'blur(10px)' }} animate={{ opacity: 1, scale: 1, filter: 'blur(0px)' }} transition={{ type: 'spring', stiffness: 200, damping: 28 }}>
      <TitleBar title={titles[view]} />
      <Sidebar view={view} onView={setView} engineOn={eng.running} reboot={eng.reboot} />
      <main className="content" ref={contentRef}>
        <AnimatePresence mode="wait">
          {view === 'dashboard' && <Dashboard key="d" />}
          {view === 'optimize' && <Optimize key="o" />}
          {view === 'tweaks' && <Tweaks key="t" />}
          {view === 'apps' && <Apps key="a" />}
          {view === 'games' && <Games key="g" />}
          {view === 'system' && <SystemTools key="y" />}
          {view === 'iso' && <IsoCreator key="i" />}
          {view === 'settings' && <SettingsView key="s" />}
        </AnimatePresence>
      </main>
      <UpdateBanner />
    </motion.div>
  )
}

export default function App() {
  const { settings } = useSettings()
  const [unlocked, setUnlocked] = useState(false)
  useEffect(() => api.auth.onLocked(() => setUnlocked(false)), [])
  useEffect(() => {
    const blur = () => document.body.classList.add('window-blurred')
    const focus = () => document.body.classList.remove('window-blurred')
    window.addEventListener('blur', blur); window.addEventListener('focus', focus)
    return () => { window.removeEventListener('blur', blur); window.removeEventListener('focus', focus) }
  }, [])
  const reduced = settings.animations !== 'full'
  return (
    <MotionConfig reducedMotion={reduced ? 'always' : 'never'} transition={settings.animations === 'off' ? { duration: 0 } : undefined}>
      <OverlayProvider>
        <EngineProvider dryDefault={settings.engine.dryRun}>
          <Backdrop />
          <AnimatePresence mode="wait">
            {unlocked ? <Shell key="shell" /> : (
              <motion.div key="lock" style={{ position: 'fixed', inset: 0 }} exit={{ opacity: 0, transition: { duration: 0.35 } }}>
                <TitleBar />
                <Lock onUnlock={() => setUnlocked(true)} />
              </motion.div>
            )}
          </AnimatePresence>
        </EngineProvider>
      </OverlayProvider>
    </MotionConfig>
  )
}
