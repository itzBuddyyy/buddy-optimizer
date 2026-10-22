import { motion } from 'motion/react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { AlertTriangle, BatteryCharging, Check, ExternalLink, FileDown, FileUp, Globe, Loader2, Play, ScanSearch, Search, ShieldOff, Undo2, X, Zap } from 'lucide-react'
import { item, page } from '@/lib/motion'
import { useSettings } from '@/lib/store'
import { useEngine } from '@/lib/engine'
import { api } from '@/lib/api'
import { DNS_PROVIDERS, PRESETS, TWEAKS, TWEAK_CATS, type TweakCat, type WuTweak } from '@/lib/winutil'
import { Select, Switch } from '@/components/Controls'
import { useConfirm, useToast } from '@/components/Overlay'
import { EngineConsole, useRunner } from '@/components/EngineConsole'
import { useT, type TKey } from '@/i18n'

export function Tweaks() {
  const t = useT()
  const { settings } = useSettings()
  const eng = useEngine()
  const run = useRunner()
  const confirm = useConfirm()
  const toast = useToast()
  const [q, setQ] = useState('')
  const [cat, setCat] = useState<TweakCat | 'all'>('all')
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [applied, setApplied] = useState<Set<string> | null>(null)
  const [scanning, setScanning] = useState(false)

  const scan = useCallback(async () => {
    setScanning(true)
    const r = await eng.query<string[]>('wuTweakState')
    setScanning(false)
    if (r) setApplied(new Set(r))
  }, [eng.query])
  useEffect(() => { if (eng.running) scan() }, [eng.running, scan])

  const needle = q.trim().toLowerCase()
  const visible = useMemo(() => TWEAKS.filter((x) => (cat === 'all' || x.cat === cat) && (!needle || x.name.toLowerCase().includes(needle) || x.desc.toLowerCase().includes(needle))), [cat, needle])
  const groups = TWEAK_CATS.map((c) => ({ c, items: visible.filter((x) => x.cat === c) })).filter((g) => g.items.length)
  const toggle = (k: string) => setSel((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n })
  const picked = TWEAKS.filter((x) => sel.has(x.key) && !x.toggle)

  async function apply(undo: boolean) {
    const risky = picked.filter((x) => x.caution)
    const body = picked.map((x) => x.name).join(', ') + (risky.length ? `\n\n${t('tw.cautionList')}: ${risky.map((x) => x.name).join(', ')}` : '')
    if (!(await confirm({ title: t(undo ? 'tw.undoN' : 'tw.applyN', { n: picked.length }), body, confirm: t(undo ? 'tw.undo' : 'tw.apply'), danger: undo || risky.length > 0 }))) return
    await run('wuTweaks', { keys: picked.map((x) => x.key), undo })
    scan()
  }

  async function flip(x: WuTweak, on: boolean) {
    await run('wuTweaks', { keys: [x.key], undo: !on })
    scan()
  }

  return (
    <motion.div variants={page} initial="initial" animate="enter" exit="exit">
      <motion.div variants={item} className="page-head">
        <div>
          <h1>{t('tw.title')}</h1>
          <p>{t('tw.subtitle')}</p>
        </div>
        <div className="row">
          {settings.engine.dryRun && <span className="tag warn">{t('opt.dryRun')}</span>}
          <span className="faint" style={{ fontSize: 12, fontWeight: 600 }}>{t('tw.presets')}</span>
          {(['Minimal', 'Standard', 'Advanced'] as const).map((p) => (
            <button key={p} className="btn sm" onClick={() => { setSel(new Set(PRESETS[p])); setCat('all') }}>{t(`tw.preset${p}` as TKey)}</button>
          ))}
        </div>
      </motion.div>

      <motion.div variants={item} className="toolbar">
        <label className="search"><Search size={15} /><input className="input" placeholder={t('tw.search', { n: TWEAKS.length })} value={q} onChange={(e) => setQ(e.target.value)} aria-label={t('tw.search', { n: TWEAKS.length })} /></label>
        <button className="btn sm" disabled={!!eng.busy || scanning} onClick={async () => { if (!eng.running && !(await eng.start()).ok) return; scan() }}>
          {scanning ? <Loader2 size={13} className="spin" /> : <ScanSearch size={13} />}{t('tw.detect')}
        </button>
        {applied && <button className="btn sm ghost" onClick={() => setSel(new Set(TWEAKS.filter((x) => !x.toggle && applied.has(x.key)).map((x) => x.key)))}>{t('tw.selectApplied')}</button>}
        <div style={{ flex: 1 }} />
        <button className="btn sm ghost" title={t('apps.import')} aria-label={t('apps.import')} onClick={async () => {
          const keys = await api.app.importList('tweaks'); if (!keys) return
          const ok = keys.filter((k) => TWEAKS.some((x) => x.key === k)); setSel(new Set(ok)); toast('ok', t('apps.imported', { n: ok.length }))
        }}><FileUp size={14} /></button>
        <button className="btn sm ghost" title={t('apps.export')} aria-label={t('apps.export')} disabled={sel.size === 0} onClick={async () => { if (await api.app.exportList('tweaks', [...sel])) toast('ok', t('apps.exported')) }}><FileDown size={14} /></button>
      </motion.div>

      <motion.div variants={item} className="chips">
        <button className={`chip ${cat === 'all' ? 'on' : ''}`} onClick={() => setCat('all')}>{t('cat.all')}<span className="n">{TWEAKS.length}</span></button>
        {TWEAK_CATS.map((c) => <button key={c} className={`chip ${cat === c ? 'on' : ''}`} onClick={() => setCat(c)}>{t(`twcat.${c}` as TKey)}<span className="n">{TWEAKS.filter((x) => x.cat === c).length}</span></button>)}
      </motion.div>

      {groups.map((g) => (
        <motion.div key={g.c} variants={item}>
          <div className="group-title">{t(`twcat.${g.c}` as TKey)}</div>
          <div className="glass rim list">
            {g.items.map((x) => {
              const isOn = applied?.has(x.key)
              return (
                <div key={x.key} className="list-row">
                  {x.toggle
                    ? <Switch checked={!!isOn} disabled={!!eng.busy || !applied} onChange={(v) => flip(x, v)} />
                    : <button role="checkbox" aria-checked={sel.has(x.key)} aria-label={x.name} className="checkbox" data-on={sel.has(x.key)} onClick={() => toggle(x.key)}>{sel.has(x.key) && <Check size={12} color="#fff" strokeWidth={3} />}</button>}
                  <div className="grow">
                    <div className="t row" style={{ gap: 8, flexWrap: 'wrap' }}>
                      {x.name}
                      {x.caution && <span className="tag warn"><AlertTriangle size={11} />{t('tw.caution')}</span>}
                      {!x.toggle && isOn && <span className="tag ok">{t('tw.applied')}</span>}
                    </div>
                    {x.desc && <div className="d">{x.desc}</div>}
                  </div>
                  {!x.toggle && isOn && <button className="btn sm ghost" disabled={!!eng.busy} onClick={async () => {
                    if (await confirm({ title: `${t('tw.undo')}: ${x.name}`, body: t('tw.undoOneD'), confirm: t('tw.undo') })) { await run('wuTweaks', { keys: [x.key], undo: true }); scan() }
                  }}><Undo2 size={13} />{t('tw.undo')}</button>}
                  {x.link && <button className="btn ghost sm" style={{ padding: '0 6px' }} aria-label={t('tw.docs')} title={t('tw.docs')} onClick={() => api.app.openExternal(x.link!)}><ExternalLink size={13} /></button>}
                </div>
              )
            })}
          </div>
        </motion.div>
      ))}

      <div className="sticky-bar glass strong rim">
        <span style={{ fontWeight: 650, fontSize: 13.5 }}>{picked.length ? t('tw.nSelected', { n: picked.length }) : t('tw.pick')}</span>
        <div className="row">
          {sel.size > 0 && <button className="btn sm ghost" onClick={() => setSel(new Set())}><X size={13} />{t('apps.clear')}</button>}
          <button className="btn sm" disabled={!picked.length || !!eng.busy} onClick={() => apply(true)}><Undo2 size={13} />{t('tw.undo')}</button>
          <button className="btn sm primary" disabled={!picked.length || !!eng.busy} onClick={() => apply(false)}>
            {eng.busy === 'wuTweaks' ? <Loader2 size={13} className="spin" /> : <Play size={13} fill="currentColor" />}{settings.engine.dryRun ? t('opt.preview') : t('tw.apply')}
          </button>
        </div>
      </div>

      <motion.div variants={item} className="section-title">{t('tw.more')}</motion.div>
      <motion.div variants={item}><ExtraTools run={run} /></motion.div>
      <div style={{ height: 16 }} />
      <EngineConsole />
    </motion.div>
  )
}

type Run = ReturnType<typeof useRunner>

function ExtraTools({ run }: { run: Run }) {
  const t = useT()
  const eng = useEngine()
  const confirm = useConfirm()
  const [dns, setDns] = useState('Cloudflare')
  const [bench, setBench] = useState<{ provider: string; ip: string; ms: number }[] | null>(null)
  const [benching, setBenching] = useState(false)
  const ask = async (title: TKey, body: TKey, action: string, args: Record<string, unknown>, danger = false) => {
    if (await confirm({ title: t(title), body: t(body), confirm: t(title), danger })) await run(action, args)
  }
  return (
    <div className="glass rim list">
      <div className="list-row">
        <span className="cico" style={{ flex: 'none' }}><Globe size={16} /></span>
        <div className="grow">
          <div className="t">{t('tw.dns')}</div>
          <div className="d">{t('tw.dnsD')}</div>
          {bench && <div className="d" style={{ marginTop: 6 }}>{bench.map((b) => `${b.provider.replace(/_/g, ' ')} ${b.ms >= 9999 ? '—' : b.ms + ' ms'}`).join(' · ')}</div>}
        </div>
        <button className="btn sm ghost" disabled={!!eng.busy || benching} onClick={async () => {
          if (!eng.running && !(await eng.start()).ok) return
          setBenching(true); setBench(await eng.query('wuDnsBench')); setBenching(false)
        }}>{benching ? <Loader2 size={13} className="spin" /> : <Zap size={13} />}{t('tw.dnsBench')}</button>
        <Select value={dns} onChange={setDns} width={200} options={DNS_PROVIDERS.map((p) => ({ value: p, label: p === 'Default' ? t('tw.dnsKeep') : p.replace(/_/g, ' ') }))} />
        <button className="btn sm primary" disabled={!!eng.busy || dns === 'Default'} onClick={() => ask('tw.dnsApply', 'tw.dnsApplyD', 'wuDns', { provider: dns })}>{t('common.apply')}</button>
      </div>
      <div className="list-row">
        <span className="cico" style={{ flex: 'none' }}><BatteryCharging size={16} /></span>
        <div className="grow"><div className="t">{t('tw.ultPerf')}</div><div className="d">{t('tw.ultPerfD')}</div></div>
        <button className="btn sm" disabled={!!eng.busy} onClick={() => ask('tw.ultPerfOff', 'tw.ultPerfOffD', 'wuExtra', { id: 'ultPerfOff' })}>{t('tw.ultPerfOff')}</button>
        <button className="btn sm primary" disabled={!!eng.busy} onClick={() => ask('tw.ultPerfOn', 'tw.ultPerfD', 'wuExtra', { id: 'ultPerfOn' })}>{t('tw.ultPerfOn')}</button>
      </div>
      <div className="list-row">
        <span className="cico" style={{ flex: 'none' }}><ShieldOff size={16} /></span>
        <div className="grow"><div className="t">O&amp;O ShutUp10++</div><div className="d">{t('tw.oosuD')}</div></div>
        <button className="btn sm" disabled={!!eng.busy} onClick={() => ask('tw.oosu', 'tw.oosuD', 'wuExtra', { id: 'oosu' })}><ExternalLink size={13} />{t('tw.oosu')}</button>
      </div>
    </div>
  )
}
