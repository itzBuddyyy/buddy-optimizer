import { motion } from 'motion/react'
import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { ExternalLink, Loader2, RefreshCw, RotateCcw, ShieldCheck, Undo2 } from 'lucide-react'
import type { EngineResult } from '@shared/types'
import { useEngine } from '@/lib/engine'
import { useMonitor } from '@/lib/store'
import { Checkbox, Switch } from '@/components/Controls'
import { useConfirm, useToast } from '@/components/Overlay'
import { useT, type TKey } from '@/i18n'
import { spring } from '@/lib/motion'

type Run = (action: string, args?: Record<string, unknown>, okText?: string) => Promise<EngineResult | null | undefined>

// Wrapper: tabs that read live system state need the elevated engine.
function NeedsEngine({ children }: { children: ReactNode }) {
  const t = useT()
  const eng = useEngine()
  const toast = useToast()
  if (eng.running) return <>{children}</>
  return (
    <div className="glass rim" style={{ padding: 28, textAlign: 'center' }}>
      <ShieldCheck size={26} style={{ color: 'var(--orchid-400)' }} />
      <div style={{ fontWeight: 650, marginTop: 10 }}>{t('opt.engineTitle')}</div>
      <div className="muted" style={{ fontSize: 13, marginTop: 4, marginBottom: 16 }}>{t('opt.needEngine')}</div>
      <button className="btn primary" disabled={eng.starting} onClick={async () => { const r = await eng.start(); if (!r.ok) toast('bad', r.error === 'uac-declined' ? t('opt.engineDeclined') : t('opt.engineFailed')) }}>
        {eng.starting ? <Loader2 size={16} className="spin" /> : <ShieldCheck size={16} />}{t('opt.engineStart')}
      </button>
    </div>
  )
}

function useQuery<T>(what: string) {
  const eng = useEngine()
  const [data, setData] = useState<T | null>(null)
  const [loading, setLoading] = useState(false)
  const load = useCallback(async () => {
    if (!eng.running) return
    setLoading(true)
    const d = await eng.query<T>(what)
    setData(d)
    setLoading(false)
  }, [eng.running, what, eng.query])
  useEffect(() => { load() }, [load])
  return { data, loading, reload: load }
}

function Loading() {
  return <div className="glass" style={{ padding: 30, display: 'grid', placeItems: 'center' }}><Loader2 className="spin" size={20} style={{ color: 'var(--orchid-400)' }} /></div>
}

function Row({ title, desc, right, left }: { title: ReactNode; desc?: ReactNode; right?: ReactNode; left?: ReactNode }) {
  return (
    <div className="list-row">
      {left}
      <div className="grow">
        <div className="t">{title}</div>
        {desc && <div className="d">{desc}</div>}
      </div>
      {right}
    </div>
  )
}

// ------------------------------------------------------------------ Debloat

interface DebloatItem { Label: string; Recommended: boolean; Installed: boolean; Note?: string }

export function DebloatTab({ run }: { run: Run }) {
  return <NeedsEngine><DebloatInner run={run} /></NeedsEngine>
}
function DebloatInner({ run }: { run: Run }) {
  const t = useT()
  const confirm = useConfirm()
  const eng = useEngine()
  const { data, loading, reload } = useQuery<DebloatItem[]>('debloat')
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [showAll, setShowAll] = useState(false)
  useEffect(() => { if (data) setSel(new Set(data.filter((d) => d.Installed && d.Recommended).map((d) => d.Label))) }, [data])
  if (loading && !data) return <Loading />
  const list = (data ?? []).filter((d) => showAll || d.Installed)
  return (
    <div className="glass rim">
      <div className="spread" style={{ padding: '16px 18px 6px' }}>
        <div className="muted" style={{ fontSize: 13, maxWidth: 640 }}>{t('debloat.body')}</div>
        <label className="row" style={{ gap: 8, fontSize: 12.5, fontWeight: 600, whiteSpace: 'nowrap' }}><Switch checked={showAll} onChange={setShowAll} />{t('debloat.showAll')}</label>
      </div>
      <div className="list">
        {list.map((d) => (
          <Row key={d.Label}
            left={<Checkbox checked={sel.has(d.Label)} disabled={!d.Installed} onChange={(v) => setSel((s) => { const n = new Set(s); if (v) n.add(d.Label); else n.delete(d.Label); return n })} />}
            title={<span className="row" style={{ gap: 8 }}>{d.Label}{d.Recommended && <span className="tag accent">{t('debloat.recommended')}</span>}{!d.Installed && <span className="tag">{t('debloat.notInstalled')}</span>}</span>}
            desc={d.Note} />
        ))}
      </div>
      <div className="spread" style={{ padding: 16, borderTop: '1px solid var(--glass-stroke)' }}>
        <span className="faint" style={{ fontSize: 12 }}>{t('debloat.warn')}</span>
        <div className="row">
          <button className="btn sm ghost" onClick={reload}><RefreshCw size={13} /></button>
          <button className="btn sm danger" disabled={sel.size === 0 || !!eng.busy} onClick={async () => {
            if (!(await confirm({ title: t('debloat.remove', { n: sel.size }), body: [...sel].join(', '), confirm: t('debloat.removeShort'), danger: true }))) return
            await run('debloat', { labels: [...sel] }); reload()
          }}>{t('debloat.remove', { n: sel.size })}</button>
        </div>
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ Startup

interface StartupItem { name: string; approved: string; where: string; command: string; enabled: boolean }

export function StartupTab({ run }: { run: Run }) {
  return <NeedsEngine><StartupInner run={run} /></NeedsEngine>
}
function StartupInner({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const { data, loading, reload } = useQuery<StartupItem[]>('startup')
  const [state, setState] = useState<Record<string, boolean>>({})
  useEffect(() => { if (data) setState(Object.fromEntries(data.map((d) => [d.approved + '|' + d.name, d.enabled]))) }, [data])
  if (loading && !data) return <Loading />
  const changes = (data ?? []).filter((d) => state[d.approved + '|' + d.name] !== d.enabled).map((d) => ({ name: d.name, approved: d.approved, enable: state[d.approved + '|' + d.name] }))
  return (
    <div className="glass rim">
      <div style={{ padding: '16px 18px 6px' }} className="muted"><span style={{ fontSize: 13 }}>{t('startup.body')}</span></div>
      <div className="list">
        {(data ?? []).length === 0 && <div className="faint" style={{ padding: 18 }}>{t('startup.empty')}</div>}
        {(data ?? []).map((d) => {
          const k = d.approved + '|' + d.name
          return <Row key={k} title={d.name} desc={<span title={d.command}>{d.where}</span>} right={<Switch checked={!!state[k]} onChange={(v) => setState((s) => ({ ...s, [k]: v }))} />} />
        })}
      </div>
      <div className="spread" style={{ padding: 16, borderTop: '1px solid var(--glass-stroke)' }}>
        <span className="faint" style={{ fontSize: 12 }}>{t('startup.note')}</span>
        <button className="btn sm primary" disabled={changes.length === 0 || !!eng.busy} onClick={async () => { await run('startup', { changes }); reload() }}>
          {t('startup.apply', { n: changes.length })}
        </button>
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ Look & feel

const LOOK: { id: string; title: TKey; desc: TKey; def: boolean }[] = [
  { id: 'visual', title: 'look.visual', desc: 'look.visualD', def: true },
  { id: 'taskbar', title: 'look.taskbar', desc: 'look.taskbarD', def: true },
  { id: 'explorer', title: 'look.explorer', desc: 'look.explorerD', def: true },
  { id: 'start', title: 'look.start', desc: 'look.startD', def: true },
  { id: 'sounds', title: 'look.sounds', desc: 'look.soundsD', def: true },
  { id: 'dark', title: 'look.dark', desc: 'look.darkD', def: false },
  { id: 'wallpaper', title: 'look.wallpaper', desc: 'look.wallpaperD', def: false }
]

export function LookTab({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const [sel, setSel] = useState<Set<string>>(new Set(LOOK.filter((l) => l.def).map((l) => l.id)))
  return (
    <div className="glass rim">
      <div style={{ padding: '16px 18px 6px' }} className="muted"><span style={{ fontSize: 13 }}>{t('look.body')}</span></div>
      <div className="list">
        {LOOK.map((l) => (
          <Row key={l.id} left={<Checkbox checked={sel.has(l.id)} onChange={(v) => setSel((s) => { const n = new Set(s); if (v) n.add(l.id); else n.delete(l.id); return n })} />}
            title={t(l.title)} desc={t(l.desc)} />
        ))}
      </div>
      <div className="spread" style={{ padding: 16, borderTop: '1px solid var(--glass-stroke)' }}>
        <span className="faint" style={{ fontSize: 12 }}>{t('look.note')}</span>
        <button className="btn sm primary" disabled={sel.size === 0 || !!eng.busy} onClick={() => run('ui', { groups: [...sel] })}>{t('common.apply')}</button>
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ GPU

export function GpuTab({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const m = useMonitor()
  const vendors = new Set((m.info?.gpus ?? []).map((g) => g.vendor))
  const hz = Number((eng.ready?.sys as { RefreshRate?: number } | undefined)?.RefreshRate ?? 0)
  const [cap, setCap] = useState<number>(hz >= 60 ? hz - 3 : 0)
  useEffect(() => { if (hz >= 60) setCap(hz - 3) }, [hz])
  const btn = (action: string, label: ReactNode, args?: Record<string, unknown>, primary = false) => (
    <button className={`btn sm ${primary ? 'primary' : ''}`} disabled={!!eng.busy} onClick={() => run(action, args)}>{label}</button>
  )
  return (
    <div className="glass rim">
      <div style={{ padding: '16px 18px 6px' }} className="muted"><span style={{ fontSize: 13 }}>{t('gpu.body')}</span></div>
      <div className="list">
        <Row title={t('gpu.driverPages')} desc={t('gpu.driverPagesD')} right={btn('driverPages', <><ExternalLink size={13} />{t('gpu.open')}</>)} />
        <Row title={t('gpu.noWu')} desc={t('gpu.noWuD')} right={btn('noWuDrivers', t('common.apply'))} />
        {vendors.has('NVIDIA') && (
          <Row title={t('gpu.nvProfile')} desc={t('gpu.nvProfileD')} right={
            <div className="row">
              <span className="faint" style={{ fontSize: 12 }}>{t('gpu.cap')}</span>
              <input className="input num" style={{ width: 76, height: 30 }} type="number" min={0} max={1000} value={cap} onChange={(e) => setCap(Math.max(0, Math.min(1000, Number(e.target.value) || 0)))} />
              {btn('nvidia', t('common.apply'), { cap }, true)}
            </div>} />
        )}
        {vendors.has('NVIDIA') && <Row title={t('gpu.openNv')} desc={t('gpu.openNvD')} right={btn('openNvidia', <><ExternalLink size={13} />{t('gpu.open')}</>)} />}
        {vendors.has('AMD') && <Row title={t('gpu.openAmd')} desc={t('gpu.openAmdD')} right={btn('openAmd', <><ExternalLink size={13} />{t('gpu.open')}</>)} />}
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ Timer resolution

export function TimerTab({ run }: { run: Run }) {
  return <NeedsEngine><TimerInner run={run} /></NeedsEngine>
}
function TimerInner({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const { data, reload } = useQuery<{ installed: boolean; state: string | null }>('timer')
  return (
    <div className="glass rim">
      <div className="list">
        <Row title={<span className="row" style={{ gap: 8 }}>{t('timer.title')}<span className={`tag ${data?.installed ? 'ok' : ''}`}>{data?.installed ? `${t('timer.installed')} · ${data.state ?? ''}` : t('timer.notInstalled')}</span></span>}
          desc={t('timer.body')}
          right={data?.installed
            ? <button className="btn sm" disabled={!!eng.busy} onClick={async () => { await run('timerRemove'); reload() }}>{t('timer.remove')}</button>
            : <button className="btn sm primary" disabled={!!eng.busy} onClick={async () => { await run('timerInstall'); reload() }}>{t('timer.install')}</button>} />
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ Advanced toggles

interface Toggle { id: string; label: string; on: boolean; info: string }

export function AdvancedTab({ run }: { run: Run }) {
  return <NeedsEngine><AdvancedInner run={run} /></NeedsEngine>
}
function AdvancedInner({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const confirm = useConfirm()
  const { data, loading, reload } = useQuery<Toggle[]>('toggles')
  if (loading && !data) return <Loading />
  const tk = (id: string, suffix = '') => `adv.${id}${suffix}` as TKey
  return (
    <div className="glass rim">
      <div style={{ padding: '16px 18px 6px' }} className="muted"><span style={{ fontSize: 13 }}>{t('adv.body')}</span></div>
      <div className="list">
        {(data ?? []).map((x) => {
          const label = t(tk(x.id)) === tk(x.id) ? x.label : t(tk(x.id))
          const info = t(tk(x.id, 'D')) === tk(x.id, 'D') ? x.info : t(tk(x.id, 'D'))
          return (
            <Row key={x.id} title={label} desc={info}
              right={<Switch checked={x.on} disabled={!!eng.busy} onChange={async (v) => {
                if (!(await confirm({ title: label, body: `${v ? t('common.on') : t('common.off')} — ${info}`, confirm: v ? t('adv.turnOn') : t('adv.turnOff') }))) return
                await run('toggle', { id: x.id, enable: v }); reload()
              }} />} />
          )
        })}
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ Repair & restore

interface Session { File: string; Date: string; Changes: number; Undone: boolean }

export function RepairTab({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const confirm = useConfirm()
  const [resetStore, setResetStore] = useState(false)
  const sessions = useQuery<Session[]>('sessions')
  const ask = async (title: TKey, body: TKey, action: string, args?: Record<string, unknown>, danger = false) => {
    if (await confirm({ title: t(title), body: t(body), confirm: t(title), danger })) { await run(action, args); sessions.reload() }
  }
  return (
    <div className="col" style={{ gap: 14 }}>
      <div className="glass rim">
        <div className="list">
          <Row title={t('rep.xboxFix')} desc={<span>{t('rep.xboxFixD')} <label className="row" style={{ gap: 8, marginTop: 8, display: 'inline-flex' }}><Checkbox checked={resetStore} onChange={setResetStore} /><span>{t('rep.resetStore')}</span></label></span>}
            right={<button className="btn sm" disabled={!!eng.busy} onClick={() => ask('rep.xboxFix', 'rep.xboxFixD', 'xboxFix', { resetStore })}>{t('common.apply')}</button>} />
          <Row title={t('rep.xboxLock')} desc={t('rep.xboxLockD')} right={<button className="btn sm" disabled={!!eng.busy} onClick={() => ask('rep.xboxLock', 'rep.xboxLockD', 'xboxLock', undefined, true)}>{t('common.apply')}</button>} />
          <Row title={t('rep.restorePower')} desc={t('rep.restorePowerD')} right={<button className="btn sm" disabled={!!eng.busy} onClick={() => ask('rep.restorePower', 'rep.restorePowerD', 'restorePower')}>{t('common.apply')}</button>} />
          <Row title={t('rep.deepNet')} desc={t('rep.deepNetD')} right={<button className="btn sm" disabled={!!eng.busy} onClick={() => ask('rep.deepNet', 'rep.deepNetD', 'deepnet', undefined, true)}>{t('common.apply')}</button>} />
          <Row title={t('rep.restorePoint')} desc={t('rep.restorePointD')} right={<button className="btn sm" disabled={!!eng.busy} onClick={() => run('restorePoint')}><RotateCcw size={13} />{t('common.create')}</button>} />
        </div>
      </div>
      <NeedsEngine>
        <div className="glass rim">
          <div className="spread" style={{ padding: '16px 18px 8px' }}>
            <div>
              <div style={{ fontWeight: 650 }}>{t('rep.undo')}</div>
              <div className="muted" style={{ fontSize: 13, marginTop: 3 }}>{t('rep.undoD')}</div>
            </div>
            <button className="btn sm ghost" onClick={sessions.reload}><RefreshCw size={13} /></button>
          </div>
          <div className="list">
            {(sessions.data ?? []).length === 0 && <div className="faint" style={{ padding: '6px 18px 18px' }}>{t('rep.noSessions')}</div>}
            {(sessions.data ?? []).slice(0, 12).map((s) => (
              <motion.div key={s.File} layout transition={spring.smooth}>
                <Row title={new Date(s.Date).toLocaleString()} desc={t('rep.changes', { n: s.Changes })}
                  right={s.Undone ? <span className="tag">{t('rep.undone')}</span> :
                    <button className="btn sm" disabled={!!eng.busy || s.Changes === 0} onClick={async () => {
                      if (await confirm({ title: t('rep.undoBtn'), body: t('confirm.undo', { n: s.Changes }), confirm: t('rep.undoBtn'), danger: true })) { await run('undo', { file: s.File }); sessions.reload() }
                    }}><Undo2 size={13} />{t('rep.undoBtn')}</button>} />
              </motion.div>
            ))}
          </div>
        </div>
      </NeedsEngine>
    </div>
  )
}
