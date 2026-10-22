import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useState, type ReactNode } from 'react'
import { AppWindow, Boxes, Check, ExternalLink, Loader2, MonitorCog, RefreshCw, ShieldCheck, Terminal, Wrench } from 'lucide-react'
import { item, page, spring } from '@/lib/motion'
import { useSettings } from '@/lib/store'
import { useEngine } from '@/lib/engine'
import { api } from '@/lib/api'
import { APPX, FEATURES, PANELS } from '@/lib/winutil'
import { Checkbox } from '@/components/Controls'
import { useConfirm } from '@/components/Overlay'
import { EngineConsole, useRunner } from '@/components/EngineConsole'
import { NeedsEngine } from './OptimizeTabs'
import { useT, type TKey } from '@/i18n'

type Tab = 'features' | 'fixes' | 'updates' | 'store' | 'panels' | 'remote'
type Run = ReturnType<typeof useRunner>

function Row({ title, desc, right, left }: { title: ReactNode; desc?: ReactNode; right?: ReactNode; left?: ReactNode }) {
  return <div className="list-row">{left}<div className="grow"><div className="t">{title}</div>{desc && <div className="d">{desc}</div>}</div>{right}</div>
}

export function SystemTools() {
  const t = useT()
  const { settings } = useSettings()
  const run = useRunner()
  const [tab, setTab] = useState<Tab>('features')
  const tabs: { id: Tab; icon: typeof Wrench; label: TKey }[] = [
    { id: 'features', icon: Boxes, label: 'sys.features' }, { id: 'fixes', icon: Wrench, label: 'sys.fixes' },
    { id: 'updates', icon: RefreshCw, label: 'sys.updates' }, { id: 'store', icon: AppWindow, label: 'sys.store' },
    { id: 'panels', icon: MonitorCog, label: 'sys.panels' }, { id: 'remote', icon: Terminal, label: 'sys.remote' }
  ]
  return (
    <motion.div variants={page} initial="initial" animate="enter" exit="exit">
      <motion.div variants={item} className="page-head">
        <div><h1>{t('sys.title')}</h1><p>{t('sys.subtitle')}</p></div>
        {settings.engine.dryRun && <span className="tag warn">{t('opt.dryRun')}</span>}
      </motion.div>
      <motion.div variants={item}>
        <div className="tabs" role="tablist">
          {tabs.map((x) => {
            const Icon = x.icon
            return (
              <button key={x.id} role="tab" aria-selected={tab === x.id} className={tab === x.id ? 'on' : ''} onClick={() => setTab(x.id)}>
                {tab === x.id && <motion.span layoutId="sys-tab" className="tab-thumb" transition={spring.snappy} />}
                <span><Icon size={14} />{t(x.label)}</span>
              </button>
            )
          })}
        </div>
        <AnimatePresence mode="wait">
          <motion.div key={tab} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -4, transition: { duration: 0.12 } }} transition={spring.smooth}>
            {tab === 'features' && <Features run={run} />}
            {tab === 'fixes' && <Fixes run={run} />}
            {tab === 'updates' && <Updates run={run} />}
            {tab === 'store' && <NeedsEngine><StoreApps run={run} /></NeedsEngine>}
            {tab === 'panels' && <Panels />}
            {tab === 'remote' && <Remote run={run} />}
          </motion.div>
        </AnimatePresence>
      </motion.div>
      <div style={{ height: 16 }} />
      <EngineConsole />
    </motion.div>
  )
}

function Features({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const confirm = useConfirm()
  const [sel, setSel] = useState<Set<string>>(new Set())
  return (
    <div className="glass rim">
      <div style={{ padding: '16px 18px 6px' }} className="muted"><span style={{ fontSize: 13 }}>{t('sys.featuresD')}</span></div>
      <div className="list">
        {FEATURES.map((f) => <Row key={f.key} left={<Checkbox checked={sel.has(f.key)} onChange={(v) => setSel((s) => { const n = new Set(s); if (v) n.add(f.key); else n.delete(f.key); return n })} />} title={f.name} desc={f.desc} />)}
      </div>
      <div className="spread" style={{ padding: 16, borderTop: '1px solid var(--glass-stroke)' }}>
        <span className="faint" style={{ fontSize: 12 }}>{t('sys.featuresNote')}</span>
        <button className="btn sm primary" disabled={!sel.size || !!eng.busy} onClick={async () => {
          if (await confirm({ title: t('sys.enableN', { n: sel.size }), body: FEATURES.filter((f) => sel.has(f.key)).map((f) => f.name).join(', '), confirm: t('sys.enable') })) { await run('wuFeatures', { keys: [...sel] }); setSel(new Set()) }
        }}>{t('sys.enableN', { n: sel.size })}</button>
      </div>
    </div>
  )
}

const FIXES: { id: string; title: TKey; desc: TKey; danger?: boolean }[] = [
  { id: 'repair', title: 'fix.repair', desc: 'fix.repairD' },
  { id: 'update', title: 'fix.update', desc: 'fix.updateD' },
  { id: 'updateDeep', title: 'fix.updateDeep', desc: 'fix.updateDeepD', danger: true },
  { id: 'network', title: 'fix.network', desc: 'fix.networkD', danger: true },
  { id: 'ntp', title: 'fix.ntp', desc: 'fix.ntpD' },
  { id: 'winget', title: 'fix.winget', desc: 'fix.wingetD' },
  { id: 'autologon', title: 'fix.autologon', desc: 'fix.autologonD' }
]

function Fixes({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const confirm = useConfirm()
  return (
    <div className="glass rim list">
      {FIXES.map((f) => (
        <Row key={f.id} title={t(f.title)} desc={t(f.desc)} right={
          <button className={`btn sm ${f.danger ? '' : 'primary'}`} disabled={!!eng.busy} onClick={async () => {
            if (await confirm({ title: t(f.title), body: t(f.desc), confirm: t('sys.run'), danger: f.danger })) await run('wuFix', { id: f.id })
          }}>{eng.busy === 'wuFix' ? <Loader2 size={13} className="spin" /> : <Wrench size={13} />}{t('sys.run')}</button>} />
      ))}
    </div>
  )
}

function Updates({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const confirm = useConfirm()
  const modes: { id: string; title: TKey; desc: TKey; tag?: TKey; danger?: boolean }[] = [
    { id: 'default', title: 'upd2.default', desc: 'upd2.defaultD' },
    { id: 'security', title: 'upd2.security', desc: 'upd2.securityD', tag: 'opt.recommended' },
    { id: 'disable', title: 'upd2.disable', desc: 'upd2.disableD', danger: true }
  ]
  return (
    <div className="cards">
      {modes.map((m) => (
        <div key={m.id} className="card glass rim">
          <div className="spread"><span className="cico"><ShieldCheck size={18} /></span>{m.tag && <span className="tag accent">{t(m.tag)}</span>}{m.danger && <span className="tag bad">{t('tw.caution')}</span>}</div>
          <h4>{t(m.title)}</h4>
          <p>{t(m.desc)}</p>
          <div className="foot"><span /><button className={`btn sm ${m.danger ? 'danger' : 'primary'}`} disabled={!!eng.busy} onClick={async () => {
            if (await confirm({ title: t(m.title), body: t(m.desc), confirm: t('common.apply'), danger: m.danger })) await run('wuUpdates', { mode: m.id })
          }}>{t('common.apply')}</button></div>
        </div>
      ))}
    </div>
  )
}

function StoreApps({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const confirm = useConfirm()
  const [names, setNames] = useState<Set<string> | null>(null)
  const [sel, setSel] = useState<Set<string>>(new Set())
  const load = async () => { const r = await eng.query<string[]>('wuAppx'); setNames(new Set(r ?? [])) }
  useEffect(() => { load() }, [])
  const isIn = (pkg: string) => !!names && [...names].some((n) => n.toLowerCase() === pkg.toLowerCase())
  const picked = APPX.filter((a) => sel.has(a.key))
  const go = async (action: 'Remove' | 'Install') => {
    if (!(await confirm({ title: t(action === 'Remove' ? 'store.removeN' : 'store.installN', { n: picked.length }), body: picked.map((a) => a.name).join(', '), confirm: t(action === 'Remove' ? 'store.remove' : 'store.install'), danger: action === 'Remove' }))) return
    await run('wuAppx', { action, keys: picked.map((a) => a.key) }); setSel(new Set()); load()
  }
  return (
    <div className="glass rim">
      <div className="spread" style={{ padding: '16px 18px 6px' }}>
        <span className="muted" style={{ fontSize: 13 }}>{t('store.body')}</span>
        <button className="btn sm ghost" onClick={load} aria-label={t('store.refresh')}>{names ? <RefreshCw size={13} /> : <Loader2 size={13} className="spin" />}</button>
      </div>
      <div className="list">
        {APPX.map((a) => (
          <Row key={a.key} left={<Checkbox checked={sel.has(a.key)} onChange={(v) => setSel((s) => { const n = new Set(s); if (v) n.add(a.key); else n.delete(a.key); return n })} />}
            title={<span className="row" style={{ gap: 8 }}>{a.name}{names && (isIn(a.pkg) ? <span className="tag ok"><Check size={11} />{t('apps.installed')}</span> : <span className="tag">{t('debloat.notInstalled')}</span>)}</span>}
            desc={a.desc} />
        ))}
      </div>
      <div className="spread" style={{ padding: 16, borderTop: '1px solid var(--glass-stroke)' }}>
        <span className="faint" style={{ fontSize: 12 }}>{t('store.note')}</span>
        <div className="row">
          <button className="btn sm" disabled={!picked.length || !!eng.busy} onClick={() => go('Install')}>{t('store.install')}</button>
          <button className="btn sm danger" disabled={!picked.length || !!eng.busy} onClick={() => go('Remove')}>{t('store.removeN', { n: picked.length })}</button>
        </div>
      </div>
    </div>
  )
}

function Panels() {
  const t = useT()
  return (
    <div className="glass rim">
      <div style={{ padding: '16px 18px 0' }} className="muted"><span style={{ fontSize: 13 }}>{t('panel.body')}</span></div>
      <div className="panel-grid">
        {PANELS.map((p) => <button key={p} className="btn" onClick={() => api.app.openPanel(p)}><ExternalLink size={14} />{t(`panel.${p}` as TKey)}</button>)}
      </div>
    </div>
  )
}

function Remote({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const confirm = useConfirm()
  const ask = async (title: TKey, body: TKey, id: string, danger = false) => {
    if (await confirm({ title: t(title), body: t(body), confirm: t('sys.run'), danger })) await run('wuExtra', { id })
  }
  return (
    <div className="glass rim list">
      <Row title={t('rem.ssh')} desc={t('rem.sshD')} right={<button className="btn sm" disabled={!!eng.busy} onClick={() => ask('rem.ssh', 'rem.sshD', 'ssh', true)}>{t('sys.enable')}</button>} />
      <Row title={t('rem.profile')} desc={t('rem.profileD')} right={
        <div className="row">
          <button className="btn sm" disabled={!!eng.busy} onClick={() => ask('rem.profileOff', 'rem.profileOffD', 'profileOff')}>{t('rem.profileOff')}</button>
          <button className="btn sm primary" disabled={!!eng.busy} onClick={() => ask('rem.profile', 'rem.profileD', 'profileOn', true)}>{t('rem.profileOn')}</button>
        </div>} />
    </div>
  )
}
