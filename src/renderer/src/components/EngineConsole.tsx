import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useRef, useState } from 'react'
import { ChevronDown, Loader2, Terminal } from 'lucide-react'
import type { EngineResult } from '@shared/types'
import { item, spring } from '@/lib/motion'
import { useEngine } from '@/lib/engine'
import { useSettings } from '@/lib/store'
import { useToast } from '@/components/Overlay'
import { useT } from '@/i18n'
import { api } from '@/lib/api'

// Runs an engine action and reports the outcome as a toast (shared by every engine screen)
export function useRunner() {
  const t = useT()
  const eng = useEngine()
  const toast = useToast()
  const { settings } = useSettings()
  return async (action: string, args?: Record<string, unknown>, okText?: string): Promise<EngineResult | null | undefined> => {
    const res = await eng.run(action, args)
    if (!res) return
    if (!res.ok) { toast('bad', res.error === 'uac-declined' ? t('opt.engineDeclined') : `${t('opt.failed')}: ${res.error ?? ''}`); return res }
    if (settings.engine.dryRun) toast('info', t('res.preview', { dry: res.stats.dry }))
    else toast(res.stats.fail ? 'bad' : 'ok', okText ?? t('res.done', { ok: res.stats.ok, skip: res.stats.skip, fail: res.stats.fail }))
    return res
  }
}

const icons: Record<string, string> = { ok: '✓', fail: '✕', skip: '–', warn: '!', info: '›', head: '', dry: '◦', text: '' }

export function EngineConsole() {
  const t = useT()
  const eng = useEngine()
  const [showLog, setShowLog] = useState(true)
  const progressPct = eng.progress ? (eng.progress.index / eng.progress.total) * 100 : 0
  return (
    <motion.section variants={item} className="console-wrap glass rim">
      <div className="console-head">
        <button className="btn ghost sm" onClick={() => setShowLog((s) => !s)} style={{ paddingLeft: 4 }}>
          <Terminal size={14} /><span style={{ fontWeight: 650 }}>{t('log.title')}</span>
          <ChevronDown size={14} style={{ transition: 'transform var(--dur-2) var(--spring)', transform: showLog ? 'none' : 'rotate(-90deg)' }} />
        </button>
        <div className="row" style={{ gap: 6 }}>
          {eng.busy && <span className="tag accent"><Loader2 size={11} className="spin" />{eng.busy}</span>}
          <button className="btn ghost sm" onClick={() => api.app.openLogs()}>{t('rep.openLogs')}</button>
          <button className="btn ghost sm" onClick={eng.clearLogs}>{t('log.clear')}</button>
        </div>
      </div>
      {eng.progress && <div className="progress"><motion.div initial={false} animate={{ width: `${progressPct}%` }} transition={spring.smooth} /></div>}
      <AnimatePresence initial={false}>
        {showLog && (
          <motion.div initial={{ height: 0 }} animate={{ height: 'auto' }} exit={{ height: 0 }} transition={spring.smooth} style={{ overflow: 'hidden' }}>
            <Console />
          </motion.div>
        )}
      </AnimatePresence>
    </motion.section>
  )
}

function Console() {
  const t = useT()
  const { logs } = useEngine()
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => { const el = ref.current; if (el) el.scrollTop = el.scrollHeight }, [logs.length])
  return (
    <div className="console" ref={ref}>
      {logs.length === 0 && <div className="faint">{t('log.empty')}</div>}
      {logs.map((l, i) => (
        <div key={i} className={`l ${l.level}`}>
          {l.level !== 'head' && <span className="lv">{icons[l.level]}</span>}
          <span>{l.level === 'head' ? `— ${l.text}` : l.text}</span>
        </div>
      ))}
    </div>
  )
}
