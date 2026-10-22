import { motion } from 'motion/react'
import { useEffect, useMemo, useState } from 'react'
import { ArrowUpCircle, Check, Download, ExternalLink, FileDown, FileUp, Loader2, RefreshCw, ScanSearch, Search, Trash2, X } from 'lucide-react'
import { item, page } from '@/lib/motion'
import { useSettings } from '@/lib/store'
import { useEngine } from '@/lib/engine'
import { api } from '@/lib/api'
import { APPS, APP_CATS, type AppCat } from '@/lib/winutil'
import { Segmented } from '@/components/Controls'
import { useConfirm, useToast } from '@/components/Overlay'
import { EngineConsole, useRunner } from '@/components/EngineConsole'
import { useT, type TKey } from '@/i18n'

export function Apps() {
  const t = useT()
  const { settings, update } = useSettings()
  const eng = useEngine()
  const run = useRunner()
  const confirm = useConfirm()
  const toast = useToast()
  const manager = settings.apps.manager
  const [q, setQ] = useState('')
  const [cat, setCat] = useState<AppCat | 'all' | 'selected'>('all')
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [installed, setInstalled] = useState<Set<string> | null>(null)
  const [scanning, setScanning] = useState(false)

  const scan = async () => {
    setScanning(true)
    const r = await eng.query<string[]>(`wuInstalled:${manager}`)
    setScanning(false)
    if (r) setInstalled(new Set(r))
  }
  useEffect(() => { if (eng.running) scan() }, [eng.running, manager])

  const needle = q.trim().toLowerCase()
  const visible = useMemo(() => APPS.filter((a) =>
    (cat === 'all' || (cat === 'selected' ? sel.has(a.key) : a.cat === cat)) &&
    (!needle || a.name.toLowerCase().includes(needle) || a.desc.toLowerCase().includes(needle))), [cat, needle, sel])
  const counts = useMemo(() => Object.fromEntries(APP_CATS.map((c) => [c, APPS.filter((a) => a.cat === c).length])), [])

  const toggle = (k: string) => setSel((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n })
  const names = () => APPS.filter((a) => sel.has(a.key)).map((a) => a.name).join(', ')

  async function act(action: 'Install' | 'Uninstall') {
    const ok = await confirm({ title: t(action === 'Install' ? 'apps.installN' : 'apps.uninstallN', { n: sel.size }), body: names(), confirm: t(action === 'Install' ? 'apps.install' : 'apps.uninstall'), danger: action === 'Uninstall' })
    if (!ok) return
    await run('wuApps', { action, keys: [...sel], manager })
    scan()
  }

  return (
    <motion.div variants={page} initial="initial" animate="enter" exit="exit">
      <motion.div variants={item} className="page-head">
        <div>
          <h1>{t('apps.title')}</h1>
          <p>{t('apps.subtitle')}</p>
        </div>
        <div className="row">
          {settings.engine.dryRun && <span className="tag warn">{t('opt.dryRun')}</span>}
          <Segmented size="sm" value={manager} onChange={(v) => update({ apps: { manager: v } })} options={[{ value: 'winget', label: 'WinGet' }, { value: 'choco', label: 'Chocolatey' }]} />
        </div>
      </motion.div>

      <motion.div variants={item} className="toolbar">
        <label className="search"><Search size={15} /><input className="input" placeholder={t('apps.search', { n: APPS.length })} value={q} onChange={(e) => setQ(e.target.value)} aria-label={t('apps.searchLabel')} /></label>
        <button className="btn sm" disabled={!!eng.busy || scanning} onClick={async () => { if (!eng.running && !(await eng.start()).ok) return; scan() }}>
          {scanning ? <Loader2 size={13} className="spin" /> : <ScanSearch size={13} />}{t('apps.detect')}
        </button>
        <button className="btn sm" disabled={!!eng.busy} onClick={async () => {
          if (await confirm({ title: t('apps.updateAll'), body: t('apps.updateAllD', { m: manager === 'choco' ? 'Chocolatey' : 'WinGet' }), confirm: t('apps.updateAll') })) { await run('wuUpgradeAll', { manager }); scan() }
        }}><ArrowUpCircle size={13} />{t('apps.updateAll')}</button>
        <div className="grow" style={{ flex: 1 }} />
        <button className="btn sm ghost" title={t('apps.import')} aria-label={t('apps.import')} onClick={async () => {
          const keys = await api.app.importList('apps'); if (!keys) return
          const known = new Set(APPS.map((a) => a.key)); const ok = keys.filter((k) => known.has(k))
          setSel(new Set(ok)); setCat('selected'); toast('ok', t('apps.imported', { n: ok.length }))
        }}><FileUp size={14} /></button>
        <button className="btn sm ghost" title={t('apps.export')} aria-label={t('apps.export')} disabled={sel.size === 0} onClick={async () => { if (await api.app.exportList('apps', [...sel])) toast('ok', t('apps.exported')) }}><FileDown size={14} /></button>
      </motion.div>

      <motion.div variants={item} className="chips" role="tablist">
        <button className={`chip ${cat === 'all' ? 'on' : ''}`} onClick={() => setCat('all')}>{t('cat.all')}<span className="n">{APPS.length}</span></button>
        {sel.size > 0 && <button className={`chip ${cat === 'selected' ? 'on' : ''}`} onClick={() => setCat('selected')}>{t('apps.selected')}<span className="n">{sel.size}</span></button>}
        {APP_CATS.map((c) => <button key={c} className={`chip ${cat === c ? 'on' : ''}`} onClick={() => setCat(c)}>{t(`appcat.${c}` as TKey)}<span className="n">{counts[c]}</span></button>)}
      </motion.div>

      <motion.div variants={item} className="app-grid">
        {visible.map((a) => {
          const isIn = installed?.has(a.key)
          return (
            <div key={a.key} className={`app-card glass rim ${sel.has(a.key) ? 'sel' : ''}`} onClick={() => toggle(a.key)} role="checkbox" aria-checked={sel.has(a.key)} tabIndex={0}
              onKeyDown={(e) => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); toggle(a.key) } }}>
              <span className="checkbox" data-on={sel.has(a.key)} aria-hidden>{sel.has(a.key) && <Check size={12} color="#fff" strokeWidth={3} />}</span>
              <div className="grow">
                <div className="t">{a.name}{isIn && <span className="tag ok">{t('apps.installed')}</span>}{a.foss && <span className="tag">FOSS</span>}{manager === 'choco' && !a.choco && <span className="tag" title={t('apps.wingetOnlyD')}>WinGet</span>}</div>
                <div className="d" title={a.desc}>{a.desc}</div>
              </div>
              {a.link && <button className="btn ghost sm" style={{ padding: '0 6px' }} aria-label={t('apps.website', { n: a.name })} onClick={(e) => { e.stopPropagation(); api.app.openExternal(a.link) }}><ExternalLink size={13} /></button>}
            </div>
          )
        })}
        {visible.length === 0 && <div className="faint" style={{ padding: 18 }}>{t('apps.none')}</div>}
      </motion.div>

      <div className="sticky-bar glass strong rim">
        <span style={{ fontWeight: 650, fontSize: 13.5 }}>{sel.size ? t('apps.nSelected', { n: sel.size }) : t('apps.pick')}</span>
        <div className="row">
          {sel.size > 0 && <button className="btn sm ghost" onClick={() => setSel(new Set())}><X size={13} />{t('apps.clear')}</button>}
          {installed && <button className="btn sm ghost" onClick={() => setSel(new Set(installed))}><RefreshCw size={13} />{t('apps.selectInstalled')}</button>}
          <button className="btn sm" disabled={sel.size === 0 || !!eng.busy} onClick={() => act('Uninstall')}><Trash2 size={13} />{t('apps.uninstall')}</button>
          <button className="btn sm primary" disabled={sel.size === 0 || !!eng.busy} onClick={() => act('Install')}>
            {eng.busy === 'wuApps' ? <Loader2 size={13} className="spin" /> : <Download size={13} />}{t('apps.install')}
          </button>
        </div>
      </div>

      <div style={{ height: 16 }} />
      <EngineConsole />
    </motion.div>
  )
}
