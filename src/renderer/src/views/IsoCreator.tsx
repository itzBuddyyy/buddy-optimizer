import { motion } from 'motion/react'
import { useCallback, useEffect, useState } from 'react'
import { Disc3, FolderOpen, HardDriveDownload, Loader2, RotateCcw, Save, Usb } from 'lucide-react'
import { item, page } from '@/lib/motion'
import { useSettings } from '@/lib/store'
import { useEngine } from '@/lib/engine'
import { api } from '@/lib/api'
import { Checkbox, Select } from '@/components/Controls'
import { useConfirm, useToast } from '@/components/Overlay'
import { EngineConsole, useRunner } from '@/components/EngineConsole'
import { NeedsEngine } from './OptimizeTabs'
import { useT } from '@/i18n'

interface IsoState { isoPath: string | null; drive: string | null; editions: { index: number; name: string }[]; defaultIndex: number | null; workDir: string | null; ready: boolean }
interface UsbDisk { number: number; name: string; sizeGB: number; style: string }

export function IsoCreator() {
  const t = useT()
  const { settings } = useSettings()
  return (
    <motion.div variants={page} initial="initial" animate="enter" exit="exit">
      <motion.div variants={item} className="page-head">
        <div><h1>{t('iso.title')}</h1><p>{t('iso.subtitle')}</p></div>
        {settings.engine.dryRun && <span className="tag warn">{t('opt.dryRun')}</span>}
      </motion.div>
      <motion.div variants={item}><NeedsEngine><Wizard /></NeedsEngine></motion.div>
      <div style={{ height: 16 }} />
      <EngineConsole />
    </motion.div>
  )
}

function Wizard() {
  const t = useT()
  const eng = useEngine()
  const run = useRunner()
  const confirm = useConfirm()
  const toast = useToast()
  const [st, setSt] = useState<IsoState | null>(null)
  const [path, setPath] = useState<string | null>(null)
  const [edition, setEdition] = useState<number>(1)
  const [drivers, setDrivers] = useState(false)
  const [usb, setUsb] = useState<UsbDisk[] | null>(null)
  const [disk, setDisk] = useState<number | null>(null)

  const take = useCallback((s: IsoState | null) => {
    if (!s) return
    setSt(s)
    if (s.isoPath) setPath(s.isoPath)
    if (s.defaultIndex) setEdition(s.defaultIndex)
  }, [])
  useEffect(() => { eng.query<IsoState>('isoState').then(take) }, [eng.query, take])

  const verified = !!st?.editions?.length
  const ready = !!st?.ready
  const busy = !!eng.busy

  async function verify() {
    if (!path) return
    const r = await run('isoVerify', { path })
    if (r?.ok && r.data) take(r.data as IsoState)
  }
  async function prepare() {
    const ed = st?.editions.find((e) => e.index === edition)
    if (!(await confirm({ title: t('iso.prepare'), body: t('iso.prepareD', { e: ed?.name ?? '' }), confirm: t('iso.prepare') }))) return
    const r = await run('isoModify', { index: edition, drivers })
    if (r?.ok && r.data) take(r.data as IsoState)
  }
  async function exportIso() {
    const out = await api.app.saveIsoAs()
    if (out) await run('isoExport', { output: out }, t('iso.saved'))
  }
  async function loadUsb() {
    const d = await eng.query<UsbDisk[]>('isoUsb')
    setUsb(d ?? []); setDisk(d?.[0]?.number ?? null)
  }
  async function writeUsb() {
    const d = usb?.find((x) => x.number === disk)
    if (!d) return
    if (!(await confirm({ title: t('iso.usbErase'), body: t('iso.usbEraseD', { d: `${d.name} (${d.sizeGB} GB)` }), confirm: t('iso.usbErase'), danger: true }))) return
    await run('isoUsb', { disk: d.number }, t('iso.usbDone'))
  }
  async function reset() {
    if (!(await confirm({ title: t('iso.reset'), body: t('iso.resetD'), confirm: t('iso.reset'), danger: true }))) return
    await run('isoReset'); setSt(null); setPath(null); setUsb(null)
    eng.query<IsoState>('isoState').then(take)
  }

  return (
    <div className="col" style={{ gap: 12 }}>
      <div className={`wizard-step glass rim`}>
        <span className="num">1</span>
        <div className="grow" style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 650 }}>{t('iso.step1')}</div>
          <div className="muted" style={{ fontSize: 13, marginTop: 3 }}>{t('iso.step1D')}</div>
          {path && <div className="mono faint" style={{ marginTop: 8 }}>{path}</div>}
          {verified && <div className="row" style={{ marginTop: 8, gap: 6, flexWrap: 'wrap' }}><span className="tag ok">{t('iso.verified', { n: st!.editions.length })}</span>{st?.drive && <span className="tag">{st.drive}</span>}</div>}
        </div>
        <div className="row">
          <button className="btn sm" disabled={busy} onClick={async () => { const p = await api.app.pickIso(); if (p) { setPath(p); setSt(null) } }}><FolderOpen size={13} />{t('iso.browse')}</button>
          <button className="btn sm primary" disabled={busy || !path} onClick={verify}>{eng.busy === 'isoVerify' ? <Loader2 size={13} className="spin" /> : <Disc3 size={13} />}{t('iso.verify')}</button>
        </div>
      </div>

      <div className={`wizard-step glass rim ${verified ? '' : 'off'}`}>
        <span className="num">2</span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 650 }}>{t('iso.step2')}</div>
          <div className="muted" style={{ fontSize: 13, marginTop: 3 }}>{t('iso.step2D')}</div>
          <label className="row" style={{ gap: 8, marginTop: 10, fontSize: 13 }}><Checkbox checked={drivers} onChange={setDrivers} /><span>{t('iso.drivers')}</span></label>
        </div>
        <div className="row">
          {verified && <Select value={edition} onChange={setEdition} width={260} options={st!.editions.map((e) => ({ value: e.index, label: `${e.index}: ${e.name}` }))} />}
          <button className="btn sm primary" disabled={busy || !verified} onClick={prepare}>{eng.busy === 'isoModify' ? <Loader2 size={13} className="spin" /> : <HardDriveDownload size={13} />}{t('iso.prepare')}</button>
        </div>
      </div>

      <div className={`wizard-step glass rim ${ready ? '' : 'off'}`}>
        <span className="num">3</span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 650 }}>{t('iso.step3')}</div>
          <div className="muted" style={{ fontSize: 13, marginTop: 3 }}>{t('iso.step3D')}</div>
          {st?.workDir && <div className="mono faint" style={{ marginTop: 8 }}>{st.workDir}</div>}
          {usb && (usb.length === 0
            ? <div className="faint" style={{ fontSize: 12.5, marginTop: 8 }}>{t('iso.noUsb')}</div>
            : <div className="row" style={{ marginTop: 10 }}>
                <Select value={disk ?? usb[0].number} onChange={setDisk} width={320} options={usb.map((d) => ({ value: d.number, label: `${t('iso.disk')} ${d.number}: ${d.name} · ${d.sizeGB} GB` }))} />
                <button className="btn sm danger" disabled={busy} onClick={writeUsb}><Usb size={13} />{t('iso.usbWrite')}</button>
              </div>)}
        </div>
        <div className="row">
          <button className="btn sm primary" disabled={busy || !ready} onClick={exportIso}><Save size={13} />{t('iso.saveIso')}</button>
          <button className="btn sm" disabled={busy || !ready} onClick={() => { loadUsb().catch(() => toast('bad', t('opt.failed'))) }}><Usb size={13} />{t('iso.usb')}</button>
        </div>
      </div>

      <div className="spread" style={{ padding: '0 6px' }}>
        <span className="faint" style={{ fontSize: 12 }}>{t('iso.note')}</span>
        <button className="btn sm ghost" disabled={busy} onClick={reset}><RotateCcw size={13} />{t('iso.reset')}</button>
      </div>
    </div>
  )
}
