import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useState, type ReactNode } from 'react'
import { Bell, Cpu, ExternalLink, Info, KeyRound, Lock, Paintbrush, Settings2, ShieldCheck, Sparkles, RefreshCw, Download, FolderOpen } from 'lucide-react'
import { item, page, spring } from '@/lib/motion'
import { useSettings } from '@/lib/store'
import { api, isPreview } from '@/lib/api'
import { Segmented, Select, Slider, Switch } from '@/components/Controls'
import { useToast } from '@/components/Overlay'
import { LANGUAGES, useT, type TKey } from '@/i18n'
import type { UpdateStatus } from '@shared/types'
import logo from '@/assets/icon.svg'
import pkg from '../../../../package.json'

type Cat = 'general' | 'appearance' | 'motion' | 'performance' | 'notifications' | 'security' | 'engine' | 'about'

const cats: { id: Cat; icon: typeof Cpu; label: TKey }[] = [
  { id: 'general', icon: Settings2, label: 'set.general' },
  { id: 'appearance', icon: Paintbrush, label: 'set.appearance' },
  { id: 'motion', icon: Sparkles, label: 'set.motion' },
  { id: 'performance', icon: Cpu, label: 'set.performance' },
  { id: 'notifications', icon: Bell, label: 'set.notifications' },
  { id: 'security', icon: Lock, label: 'set.security' },
  { id: 'engine', icon: ShieldCheck, label: 'set.engine' },
  { id: 'about', icon: Info, label: 'set.about' }
]

function Setting({ title, desc, children }: { title: ReactNode; desc?: ReactNode; children?: ReactNode }) {
  return (
    <div className="setting">
      <div className="txt">
        <div className="t">{title}</div>
        {desc && <div className="d">{desc}</div>}
      </div>
      {children}
    </div>
  )
}

function Group({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <div className="group">
      {title && <div className="group-title">{title}</div>}
      <div className="glass rim">{children}</div>
    </div>
  )
}

export function SettingsView() {
  const t = useT()
  const [cat, setCat] = useState<Cat>('general')
  return (
    <motion.div variants={page} initial="initial" animate="enter" exit="exit">
      <motion.div variants={item} className="page-head">
        <div><h1>{t('set.title')}</h1><p>{t('set.subtitle')}</p></div>
      </motion.div>
      <motion.div variants={item} className="settings">
        <nav className="settings-nav glass rim">
          {cats.map((c) => {
            const Icon = c.icon
            return (
              <button key={c.id} className={cat === c.id ? 'on' : ''} onClick={() => setCat(c.id)}>
                {cat === c.id && <motion.span layoutId="set-nav" className="nav-thumb" transition={spring.snappy} />}
                <Icon size={16} /><span>{t(c.label)}</span>
              </button>
            )
          })}
        </nav>
        <div>
          <AnimatePresence mode="wait">
            <motion.div key={cat} initial={{ opacity: 0, x: 12, filter: 'blur(4px)' }} animate={{ opacity: 1, x: 0, filter: 'blur(0px)' }} exit={{ opacity: 0, x: -8, transition: { duration: 0.12 } }} transition={spring.smooth}>
              {cat === 'general' && <General />}
              {cat === 'appearance' && <Appearance />}
              {cat === 'motion' && <MotionSettings />}
              {cat === 'performance' && <Performance />}
              {cat === 'notifications' && <Notifications />}
              {cat === 'security' && <Security />}
              {cat === 'engine' && <EngineSettings />}
              {cat === 'about' && <About />}
            </motion.div>
          </AnimatePresence>
        </div>
      </motion.div>
    </motion.div>
  )
}

function General() {
  const t = useT()
  const { settings: s, update } = useSettings()
  return (
    <>
      <Group>
        <Setting title={t('set.language')} desc={t('set.languageD')}>
          <Select value={s.language} options={LANGUAGES} onChange={(v) => update({ language: v })} />
        </Setting>
        <Setting title={t('set.launch')} desc={t('set.launchD')}><Switch checked={s.launchAtStartup} onChange={(v) => update({ launchAtStartup: v })} /></Setting>
        <Setting title={t('set.startMin')} desc={t('set.startMinD')}><Switch checked={s.startMinimized} onChange={(v) => update({ startMinimized: v })} /></Setting>
        <Setting title={t('set.closeTray')} desc={t('set.closeTrayD')}><Switch checked={s.closeToTray} onChange={(v) => update({ closeToTray: v })} /></Setting>
        <Setting title={t('set.updates')} desc={t('set.updatesD')}><Switch checked={s.checkUpdates} onChange={(v) => update({ checkUpdates: v })} /></Setting>
      </Group>
    </>
  )
}

function RestartHint({ show }: { show: boolean }) {
  const t = useT()
  return (
    <AnimatePresence>
      {show && (
        <motion.div initial={{ opacity: 0, y: -6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={spring.smooth} className="result glass" style={{ marginTop: 0, marginBottom: 16 }}>
          <div style={{ flex: 1, fontSize: 13 }} className="muted">{t('set.needsRestart')}</div>
          <button className="btn sm primary" onClick={() => api.app.relaunch()}><RefreshCw size={13} />{t('common.restart')}</button>
        </motion.div>
      )}
    </AnimatePresence>
  )
}

function Appearance() {
  const t = useT()
  const { settings: s, update } = useSettings()
  const [initialMaterial] = useState(s.nativeMaterial)
  return (
    <>
      <RestartHint show={s.nativeMaterial !== initialMaterial} />
      <Group>
        <Setting title={t('set.theme')} desc={t('set.themeD')}>
          <Segmented value={s.theme} onChange={(v) => update({ theme: v })} options={[{ value: 'dark', label: t('set.themeDark') }, { value: 'light', label: t('set.themeLight') }, { value: 'system', label: t('set.themeSystem') }]} />
        </Setting>
        <Setting title={t('set.glass')} desc={t('set.glassD')}><Slider value={s.glass} min={0} max={100} onChange={(v) => update({ glass: v })} format={(v) => `${v}%`} /></Setting>
        <Setting title={t('set.controls')} desc={t('set.controlsD')}>
          <Segmented value={s.windowControls} onChange={(v) => update({ windowControls: v })} options={[{ value: 'mac', label: t('set.controlsMac') }, { value: 'windows', label: t('set.controlsWin') }]} />
        </Setting>
        <Setting title={t('set.density')} desc={t('set.densityD')}>
          <Segmented value={s.density} onChange={(v) => update({ density: v })} options={[{ value: 'comfortable', label: t('set.comfortable') }, { value: 'compact', label: t('set.compact') }]} />
        </Setting>
        <Setting title={t('set.scale')} desc={t('set.scaleD')}><Slider value={s.uiScale} min={90} max={125} step={5} onChange={(v) => update({ uiScale: v })} format={(v) => `${v}%`} /></Setting>
        <Setting title={t('set.material')} desc={api.platform.isWin11 ? t('set.materialD') : t('set.materialWin10')}>
          <Switch checked={s.nativeMaterial} disabled={!api.platform.isWin11} onChange={(v) => update({ nativeMaterial: v })} />
        </Setting>
      </Group>
    </>
  )
}

function MotionSettings() {
  const t = useT()
  const { settings: s, update } = useSettings()
  return (
    <Group>
      <Setting title={t('set.animations')} desc={t('set.animationsD')}>
        <Segmented value={s.animations} onChange={(v) => update({ animations: v })} options={[{ value: 'full', label: t('set.animFull') }, { value: 'reduced', label: t('set.animReduced') }, { value: 'off', label: t('set.animOff') }]} />
      </Setting>
    </Group>
  )
}

function Performance() {
  const t = useT()
  const { settings: s, update } = useSettings()
  const [initialHw] = useState(s.hardwareAcceleration)
  const [host, setHost] = useState(s.pingHost)
  return (
    <>
      <RestartHint show={s.hardwareAcceleration !== initialHw} />
      <Group>
        <Setting title={t('set.hwAccel')} desc={t('set.hwAccelD')}><Switch checked={s.hardwareAcceleration} onChange={(v) => update({ hardwareAcceleration: v })} /></Setting>
        <Setting title={t('set.refresh')} desc={t('set.refreshD')}>
          <Segmented value={s.refreshMs} onChange={(v) => update({ refreshMs: v })} options={[{ value: 500, label: '0.5 s' }, { value: 1000, label: '1 s' }, { value: 2000, label: '2 s' }]} />
        </Setting>
        <Setting title={t('set.pause')} desc={t('set.pauseD')}><Switch checked={s.pauseWhenHidden} onChange={(v) => update({ pauseWhenHidden: v })} /></Setting>
        <Setting title={t('set.unit')} desc={t('set.unitD')}>
          <Segmented value={s.tempUnit} onChange={(v) => update({ tempUnit: v })} options={[{ value: 'C', label: '°C' }, { value: 'F', label: '°F' }]} />
        </Setting>
        <Setting title={t('set.pingHost')} desc={t('set.pingHostD')}>
          <input className="input" style={{ width: 200 }} value={host} spellCheck={false} onChange={(e) => setHost(e.target.value)} onBlur={() => update({ pingHost: host.trim() || '1.1.1.1' })} onKeyDown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()} />
        </Setting>
      </Group>
    </>
  )
}

function Threshold({ value, onChange, unit, options }: { value: number; onChange: (v: number) => void; unit: string; options: number[] }) {
  const t = useT()
  return <Select width={130} value={value} onChange={onChange} options={[{ value: 0, label: t('set.off') }, ...options.map((o) => ({ value: o, label: `${o}${unit}` }))]} />
}

function Notifications() {
  const t = useT()
  const { settings: s, update } = useSettings()
  const n = s.notifications
  const unit = s.tempUnit === 'F' ? '°F' : '°C'
  return (
    <>
      <Group>
        <Setting title={t('set.notif')} desc={t('set.notifD')}><Switch checked={n.enabled} onChange={(v) => update({ notifications: { enabled: v } })} /></Setting>
        <Setting title={t('set.notifDone')} desc={t('set.notifDoneD')}><Switch checked={n.onComplete} disabled={!n.enabled} onChange={(v) => update({ notifications: { onComplete: v } })} /></Setting>
      </Group>
      <Group title={t('set.alerts')}>
        <Setting title={t('set.gpuTemp')} desc={t('set.alertD')}><Threshold value={n.gpuTemp} unit="°C" options={[75, 80, 85, 90, 95]} onChange={(v) => update({ notifications: { gpuTemp: v } })} /></Setting>
        <Setting title={t('set.cpuLoad')} desc={t('set.alertD')}><Threshold value={n.cpuLoad} unit="%" options={[80, 90, 95]} onChange={(v) => update({ notifications: { cpuLoad: v } })} /></Setting>
        <Setting title={t('set.ramLoad')} desc={t('set.alertD')}><Threshold value={n.ramLoad} unit="%" options={[80, 85, 90, 95]} onChange={(v) => update({ notifications: { ramLoad: v } })} /></Setting>
        <Setting title={t('set.pingAlert')} desc={t('set.alertD')}><Threshold value={n.ping} unit=" ms" options={[40, 60, 80, 100, 150]} onChange={(v) => update({ notifications: { ping: v } })} /></Setting>
        <Setting title={t('set.test')} desc={unit === '°F' ? t('set.tempNoteF') : undefined}><button className="btn sm" disabled={!n.enabled} onClick={() => api.app.testNotification()}><Bell size={13} />{t('set.testBtn')}</button></Setting>
      </Group>
    </>
  )
}

function Security() {
  const t = useT()
  const toast = useToast()
  const { settings: s, update } = useSettings()
  const [cur, setCur] = useState('')
  const [next, setNext] = useState('')
  const [again, setAgain] = useState('')
  const [busy, setBusy] = useState(false)
  // password changes are reserved for the owner's PC (checked again in the main process)
  const [owner, setOwner] = useState(false)
  useEffect(() => { api.auth.isOwner().then(setOwner).catch(() => setOwner(false)) }, [])
  async function change() {
    if (next.length < 6) { toast('bad', t('set.pwShort')); return }
    if (next !== again) { toast('bad', t('set.pwMismatch')); return }
    setBusy(true)
    const r = await api.auth.change(cur, next)
    setBusy(false)
    if (r.ok) { toast('ok', t('set.pwChanged')); setCur(''); setNext(''); setAgain('') }
    else toast('bad', r.error === 'wrong' ? t('set.pwWrong') : r.error === 'not-owner' ? t('set.pwOwner') : t('set.pwShort'))
  }
  return (
    <>
      <Group>
        <Setting title={t('set.autolock')} desc={t('set.autolockD')}>
          <Select width={150} value={s.security.autoLockMinutes} onChange={(v) => update({ security: { autoLockMinutes: v } })}
            options={[{ value: 0, label: t('set.never') }, { value: 5, label: t('set.minutes', { n: 5 }) }, { value: 15, label: t('set.minutes', { n: 15 }) }, { value: 30, label: t('set.minutes', { n: 30 }) }]} />
        </Setting>
        <Setting title={t('set.lockNow')} desc={t('set.lockNowD')}><button className="btn sm" onClick={() => api.auth.lock()}><Lock size={13} />{t('nav.lock')}</button></Setting>
      </Group>
      {owner && <Group title={t('set.changePw')}>
        <div style={{ padding: 18, display: 'grid', gap: 10, maxWidth: 420 }}>
          <input className="input" type="password" placeholder={t('set.currentPw')} value={cur} onChange={(e) => setCur(e.target.value)} autoComplete="current-password" />
          <input className="input" type="password" placeholder={t('set.newPw')} value={next} onChange={(e) => setNext(e.target.value)} autoComplete="new-password" />
          <input className="input" type="password" placeholder={t('set.confirmPw')} value={again} onChange={(e) => setAgain(e.target.value)} autoComplete="new-password" onKeyDown={(e) => e.key === 'Enter' && change()} />
          <div><button className="btn primary sm" disabled={!cur || !next || busy} onClick={change}><KeyRound size={13} />{t('set.changePw')}</button></div>
          <div className="faint" style={{ fontSize: 12, lineHeight: 1.5 }}>{t('set.lockNote')}</div>
        </div>
      </Group>}
    </>
  )
}

function EngineSettings() {
  const t = useT()
  const { settings: s, update } = useSettings()
  return (
    <Group>
      <Setting title={t('set.xbox')} desc={t('set.xboxD')}>
        <Segmented value={s.engine.xboxMode} onChange={(v) => update({ engine: { xboxMode: v } })} options={[{ value: 'auto', label: t('opt.xboxAuto') }, { value: 'on', label: t('opt.xboxOn') }, { value: 'off', label: t('opt.xboxOff') }]} />
      </Setting>
      <Setting title={t('set.dry')} desc={t('set.dryD')}><Switch checked={s.engine.dryRun} onChange={(v) => update({ engine: { dryRun: v } })} /></Setting>
      <Setting title={t('set.rp')} desc={t('set.rpD')}><Switch checked={s.engine.restorePointFirst} onChange={(v) => update({ engine: { restorePointFirst: v } })} /></Setting>
      <Setting title={t('set.logs')} desc={t('set.logsD')}><button className="btn sm" onClick={() => api.app.openLogs()}><FolderOpen size={13} />{t('set.open')}</button></Setting>
    </Group>
  )
}

function About() {
  const t = useT()
  const [u, setU] = useState<UpdateStatus>({ state: 'idle' })
  useEffect(() => api.app.onUpdate(setU), [])
  const label = { idle: t('set.checkUpdates'), checking: t('set.checking'), none: t('set.upToDate'), available: t('set.updateAvail', { v: u.version ?? '' }), downloading: `${t('set.downloading')} ${u.percent ?? 0}%`, ready: t('set.updateReady', { v: u.version ?? '' }), error: t('set.updateError') }[u.state]
  return (
    <>
      <div className="about-hero glass strong rim" style={{ marginBottom: 16 }}>
        <img src={logo} alt="" />
        <div style={{ flex: 1 }}>
          <h2>Buddy Optimizer</h2>
          <div className="muted" style={{ marginTop: 4 }}>{t('set.version')} {pkg.version}{isPreview ? ' · preview' : ''} · Electron {api.platform.version}</div>
        </div>
        {u.state === 'ready'
          ? <button className="btn primary" onClick={() => api.app.installUpdate()}><Download size={15} />{t('set.installRestart')}</button>
          : <button className="btn" disabled={u.state === 'checking' || u.state === 'downloading'} onClick={() => { setU({ state: 'checking' }); api.app.checkUpdates() }}><RefreshCw size={14} className={u.state === 'checking' ? 'spin' : ''} />{label}</button>}
      </div>
      <Group title={t('set.credits')}>
        <Setting title="itzBuddy" desc={t('set.creditsD')}><button className="btn sm" onClick={() => api.app.openExternal(pkg.homepage)}><ExternalLink size={13} />GitHub</button></Setting>
        <Setting title={t('set.licenses')} desc="Electron · React · Motion · Lucide · Inter (OFL) · LibreHardwareMonitorLib (MPL-2.0) · NVIDIA Profile Inspector (MIT)" />
      </Group>
    </>
  )
}
