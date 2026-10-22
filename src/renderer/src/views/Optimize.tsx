import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useState } from 'react'
import {
  BatteryCharging, Brush, Check, CheckCircle2, Cpu, Eraser, Gamepad2, Loader2, Play, RotateCcw, ShieldCheck,
  ShieldAlert, SlidersHorizontal, Sparkles, Timer, Trash2, Wifi, Wrench, EyeOff, Rocket, MonitorSmartphone, AlertTriangle
} from 'lucide-react'
import { item, page, spring } from '@/lib/motion'
import { useSettings } from '@/lib/store'
import { useEngine } from '@/lib/engine'
import { Segmented, Select, Switch } from '@/components/Controls'
import { useConfirm, useToast } from '@/components/Overlay'
import { useT, type TKey } from '@/i18n'
import { api } from '@/lib/api'
import { EngineConsole, useRunner } from '@/components/EngineConsole'
import { DebloatTab, StartupTab, LookTab, GpuTab, TimerTab, AdvancedTab, RepairTab } from './OptimizeTabs'

const STEPS: { id: string; key: TKey }[] = [
  { id: 'restorePoint', key: 'step.restorePoint' },
  { id: 'power', key: 'step.power' },
  { id: 'gaming', key: 'step.gaming' },
  { id: 'services', key: 'step.services' },
  { id: 'privacy', key: 'step.privacy' },
  { id: 'cleanup', key: 'step.cleanup' }
]

type Tab = 'debloat' | 'startup' | 'look' | 'gpu' | 'timer' | 'advanced' | 'repair'

export function Optimize() {
  const t = useT()
  const { settings, update } = useSettings()
  const eng = useEngine()
  const toast = useToast()
  const confirm = useConfirm()
  const [tab, setTab] = useState<Tab>('debloat')
  const [plan, setPlan] = useState<'1' | '2' | '3'>('1')
  // laptops default to High Performance (keeps boost behaviour and battery sane)
  const isLaptop = Boolean((eng.ready?.sys as { IsLaptop?: boolean } | undefined)?.IsLaptop)
  useEffect(() => { if (isLaptop) setPlan('3') }, [isLaptop])
  const dry = settings.engine.dryRun
  const runAction = useRunner()

  async function startEngine() {
    const r = await eng.start()
    if (!r.ok) toast('bad', r.error === 'uac-declined' ? t('opt.engineDeclined') : t('opt.engineFailed'))
  }

  async function quick() {
    const ok = await confirm({ title: t('confirm.quickTitle'), body: dry ? t('confirm.quickDry') : t('confirm.quick'), confirm: dry ? t('opt.preview') : t('opt.run') })
    if (ok) await runAction('quick')
  }

  const running = eng.busy === 'quick'
  const stepIdx = running && eng.progress ? eng.progress.index : 0

  const cards: { id: string; icon: typeof Cpu; title: TKey; body: TKey; extra?: React.ReactNode; args?: () => Record<string, unknown> }[] = [
    { id: 'power', icon: BatteryCharging, title: 'act.power', body: 'act.powerBody', args: () => ({ choice: plan }),
      extra: <Select value={plan} onChange={setPlan} width={210} options={[{ value: '1', label: t('power.bitsum') }, { value: '2', label: t('power.ultimate') }, { value: '3', label: t('power.high') }]} /> },
    { id: 'gaming', icon: Gamepad2, title: 'act.gaming', body: 'act.gamingBody' },
    { id: 'services', icon: Cpu, title: 'act.services', body: 'act.servicesBody' },
    { id: 'privacy', icon: EyeOff, title: 'act.privacy', body: 'act.privacyBody' },
    { id: 'cleanup', icon: Eraser, title: 'act.cleanup', body: 'act.cleanupBody' },
    { id: 'network', icon: Wifi, title: 'act.network', body: 'act.networkBody' }
  ]

  const tabs: { id: Tab; icon: typeof Cpu; label: TKey }[] = [
    { id: 'debloat', icon: Trash2, label: 'tab.debloat' },
    { id: 'startup', icon: Rocket, label: 'tab.startup' },
    { id: 'look', icon: Brush, label: 'tab.look' },
    { id: 'gpu', icon: MonitorSmartphone, label: 'tab.gpu' },
    { id: 'timer', icon: Timer, label: 'tab.timer' },
    { id: 'advanced', icon: SlidersHorizontal, label: 'tab.advanced' },
    { id: 'repair', icon: Wrench, label: 'tab.repair' }
  ]

  return (
    <motion.div variants={page} initial="initial" animate="enter" exit="exit">
      <motion.div variants={item} className="page-head">
        <div>
          <h1>{t('opt.title')}</h1>
          <p>{t('opt.subtitle')}</p>
        </div>
        <div className="row">
          <span className="faint" style={{ fontSize: 12, fontWeight: 600 }}>{t('opt.xbox')}</span>
          <Segmented size="sm" value={settings.engine.xboxMode} onChange={(v) => update({ engine: { xboxMode: v } })}
            options={[{ value: 'auto', label: t('opt.xboxAuto') }, { value: 'on', label: t('opt.xboxOn') }, { value: 'off', label: t('opt.xboxOff') }]} />
        </div>
      </motion.div>

      {/* ---------- engine gate */}
      <AnimatePresence initial={false}>
        {!eng.running && (
          <motion.section className="engine-gate glass rim" initial={{ opacity: 0, height: 0, marginBottom: 0 }} animate={{ opacity: 1, height: 'auto', marginBottom: 16 }} exit={{ opacity: 0, height: 0, marginBottom: 0, paddingTop: 0, paddingBottom: 0 }} transition={spring.smooth}>
            <div className="shield"><ShieldCheck size={22} /></div>
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 650, fontSize: 15 }}>{t('opt.engineTitle')}</div>
              <div className="muted" style={{ fontSize: 13, marginTop: 3 }}>{t('opt.engineBody')}</div>
            </div>
            <button className="btn primary" onClick={startEngine} disabled={eng.starting}>
              {eng.starting ? <><Loader2 size={16} className="spin" />{t('opt.engineStarting')}</> : <><ShieldCheck size={16} />{t('opt.engineStart')}</>}
            </button>
          </motion.section>
        )}
      </AnimatePresence>
      {eng.running && eng.ready && !eng.ready.wmi && (
        <motion.div variants={item} className="result glass" style={{ marginTop: 0, marginBottom: 16 }}>
          <span className="ri" style={{ background: 'rgba(255,197,107,.16)', color: 'var(--warn)' }}><AlertTriangle size={17} /></span>
          <div className="muted" style={{ fontSize: 13 }}>{t('opt.wmiWarn')}</div>
        </motion.div>
      )}

      {/* ---------- quick optimize */}
      <motion.section variants={item} className="quick glass strong rim" style={{ position: 'relative' }}>
        <div className="quick-orb" />
        <div style={{ position: 'relative' }}>
          <span className="tag accent"><Sparkles size={12} />{t('opt.recommended')}</span>
          <h2>{t('opt.quick')}</h2>
          <p>{t('opt.quickBody')}</p>
          <div className="controls">
            <motion.button className="btn primary lg shine" onClick={quick} disabled={!!eng.busy} whileTap={{ scale: 0.96 }}>
              {running ? <><Loader2 size={18} className="spin" />{t('opt.running')}</> : <><Play size={17} fill="currentColor" />{dry ? t('opt.preview') : t('opt.run')}</>}
            </motion.button>
            <label className="row" style={{ gap: 10, fontSize: 13, fontWeight: 600 }}>
              <Switch checked={dry} onChange={(v) => update({ engine: { dryRun: v } })} />
              <span>{t('opt.dryRun')}</span>
            </label>
          </div>
          {dry && <div className="faint" style={{ fontSize: 12, marginTop: 10 }}>{t('opt.dryRunHint')}</div>}
        </div>
        <div className="steps" style={{ position: 'relative' }}>
          {STEPS.map((s, i) => {
            const n = i + 1
            const state = running ? (n < stepIdx ? 'done' : n === stepIdx ? 'active' : '') : (eng.last?.action === 'quick' && eng.last.ok ? 'done' : '')
            const skipped = s.id === 'restorePoint' && !settings.engine.restorePointFirst
            return (
              <div key={s.id} className={`step ${state}`} style={{ opacity: skipped ? 0.4 : 1 }}>
                <span className="n">{state === 'done' ? <Check size={13} strokeWidth={3} /> : state === 'active' ? <Loader2 size={12} className="spin" /> : n}</span>
                {t(s.key)}
              </div>
            )
          })}
        </div>
      </motion.section>

      {/* ---------- result banner */}
      <AnimatePresence>
        {eng.last && !eng.busy && (
          <motion.div className="result glass rim" initial={{ opacity: 0, y: -6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={spring.smooth}>
            <span className="ri" style={{ background: eng.last.ok && !eng.last.stats.fail ? 'rgba(95,224,165,.16)' : 'rgba(255,107,138,.16)', color: eng.last.ok && !eng.last.stats.fail ? 'var(--ok)' : 'var(--bad)' }}>
              {eng.last.ok && !eng.last.stats.fail ? <CheckCircle2 size={18} /> : <ShieldAlert size={18} />}
            </span>
            <div style={{ flex: 1, fontSize: 13.5 }}>
              <div style={{ fontWeight: 650 }}>{eng.last.dry ? t('res.preview', { dry: eng.last.stats.dry }) : eng.last.ok ? t('res.done', { ok: eng.last.stats.ok, skip: eng.last.stats.skip, fail: eng.last.stats.fail }) : `${t('opt.failed')}: ${eng.last.error ?? ''}`}</div>
              {eng.reboot && <div className="muted" style={{ marginTop: 2 }}>{t('res.reboot')}</div>}
            </div>
            {eng.reboot && (
              <button className="btn sm" onClick={async () => { if (await confirm({ title: t('res.rebootNow'), body: t('confirm.reboot'), confirm: t('res.rebootNow') })) api.app.reboot() }}>
                <RotateCcw size={14} />{t('res.rebootNow')}
              </button>
            )}
          </motion.div>
        )}
      </AnimatePresence>

      {/* ---------- individual tweaks */}
      <motion.div variants={item} className="section-title">{t('opt.individual')}</motion.div>
      <motion.div variants={item} className="cards">
        {cards.map((c) => {
          const Icon = c.icon
          const busyHere = eng.busy === c.id
          return (
            <motion.div key={c.id} className="card glass rim" whileHover={{ y: -3 }} transition={spring.snappy}>
              <div className="spread"><span className="cico"><Icon size={18} /></span><span className="tag">{t('opt.oneClick')}</span></div>
              <h4>{t(c.title)}</h4>
              <p>{t(c.body)}</p>
              <div className="foot">
                {c.extra ?? <span />}
                <button className="btn sm" disabled={!!eng.busy} onClick={() => runAction(c.id, c.args?.())}>
                  {busyHere ? <Loader2 size={14} className="spin" /> : <Play size={13} fill="currentColor" />}{dry ? t('opt.preview') : t('common.apply')}
                </button>
              </div>
            </motion.div>
          )
        })}
      </motion.div>

      {/* ---------- optional tools */}
      <motion.div variants={item} className="section-title">{t('opt.optional')}</motion.div>
      <motion.div variants={item}>
        <div className="tabs" role="tablist">
          {tabs.map((x) => {
            const Icon = x.icon
            return (
              <button key={x.id} role="tab" aria-selected={tab === x.id} className={tab === x.id ? 'on' : ''} onClick={() => setTab(x.id)}>
                {tab === x.id && <motion.span layoutId="opt-tab" className="tab-thumb" transition={spring.snappy} />}
                <span><Icon size={14} />{t(x.label)}</span>
              </button>
            )
          })}
        </div>
        <AnimatePresence mode="wait">
          <motion.div key={tab} initial={{ opacity: 0, y: 8, filter: 'blur(4px)' }} animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }} exit={{ opacity: 0, y: -4, filter: 'blur(3px)', transition: { duration: 0.12 } }} transition={spring.smooth}>
            {tab === 'debloat' && <DebloatTab run={runAction} />}
            {tab === 'startup' && <StartupTab run={runAction} />}
            {tab === 'look' && <LookTab run={runAction} />}
            {tab === 'gpu' && <GpuTab run={runAction} />}
            {tab === 'timer' && <TimerTab run={runAction} />}
            {tab === 'advanced' && <AdvancedTab run={runAction} />}
            {tab === 'repair' && <RepairTab run={runAction} />}
          </motion.div>
        </AnimatePresence>
      </motion.div>

      <EngineConsole />
    </motion.div>
  )
}
