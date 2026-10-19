import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { EngineLog, EngineProgress, EngineReady, EngineResult } from '@shared/types'
import { api } from './api'

// Engine state shared by the Optimize screen and the sidebar status chip.

interface EngineCtx {
  running: boolean
  starting: boolean
  ready: EngineReady | null
  busy: string | null
  logs: EngineLog[]
  progress: EngineProgress | null
  last: (EngineResult & { action: string; dry: boolean }) | null
  reboot: boolean
  start: () => Promise<{ ok: boolean; error?: string }>
  run: (action: string, args?: Record<string, unknown>, opts?: { dryRun?: boolean }) => Promise<EngineResult | null>
  query: <T>(what: string) => Promise<T | null>
  clearLogs: () => void
}

const Ctx = createContext<EngineCtx>(null as unknown as EngineCtx)
export const useEngine = () => useContext(Ctx)

export function EngineProvider({ children, dryDefault }: { children: ReactNode; dryDefault: boolean }) {
  const [running, setRunning] = useState(false)
  const [starting, setStarting] = useState(false)
  const [ready, setReady] = useState<EngineReady | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [logs, setLogs] = useState<EngineLog[]>([])
  const [progress, setProgress] = useState<EngineProgress | null>(null)
  const [last, setLast] = useState<EngineCtx['last']>(null)
  const [reboot, setReboot] = useState(false)
  const busyRef = useRef<string | null>(null)

  useEffect(() => {
    api.engine.status().then((s) => { setRunning(s.running); if (s.ready) setReady(s.ready) })
    const a = api.engine.onLog((l) => setLogs((x) => (x.length > 1500 ? [...x.slice(-1200), l] : [...x, l])))
    const b = api.engine.onProgress(setProgress)
    const c = api.engine.onExit(() => { setRunning(false); setReady(null) })
    return () => { a(); b(); c() }
  }, [])

  const start = useCallback(async () => {
    setStarting(true)
    const r = await api.engine.start()
    setStarting(false)
    if (r.ok) { setRunning(true); setReady(r.ready ?? null) }
    return r
  }, [])

  const run = useCallback(async (action: string, args?: Record<string, unknown>, opts?: { dryRun?: boolean }) => {
    if (busyRef.current) return null           // one engine job at a time
    busyRef.current = action
    setBusy(action)
    setProgress(null)
    try {
      const res = await api.engine.run(action, args, opts)
      const st = await api.engine.status()          // run() may have started the agent (UAC)
      setRunning(st.running)
      if (st.ready) setReady(st.ready)
      const dry = opts?.dryRun ?? dryDefault
      setLast({ ...res, action, dry })
      if (res.reboot && !dry) setReboot(true)
      return res
    } finally {
      busyRef.current = null
      setBusy(null)
      setProgress(null)
    }
  }, [dryDefault])

  const query = useCallback(async <T,>(what: string) => {
    try { return (await api.engine.query<T>(what)) ?? null } catch { return null }
  }, [])

  const value = useMemo<EngineCtx>(() => ({ running, starting, ready, busy, logs, progress, last, reboot, start, run, query, clearLogs: () => setLogs([]) }),
    [running, starting, ready, busy, logs, progress, last, reboot, start, run, query])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}
