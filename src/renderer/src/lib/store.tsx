import { createContext, useContext, useEffect, useMemo, useState, useSyncExternalStore, type ReactNode } from 'react'
import { MotionGlobalConfig } from 'motion/react'
import type { DeepPartial, MonitorInfo, MonitorTick, Settings } from '@shared/types'
import { DEFAULT_SETTINGS } from '@shared/types'
import { api } from './api'

// ------------------------------------------------------------------ settings

interface SettingsCtx { settings: Settings; update: (p: DeepPartial<Settings>) => Promise<void> }
const SettingsContext = createContext<SettingsCtx>({ settings: DEFAULT_SETTINGS, update: async () => {} })

function applyToDocument(s: Settings) {
  const el = document.documentElement
  const dark = s.theme === 'dark' || (s.theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches)
  el.dataset.theme = dark ? 'dark' : 'light'
  // "full" still honours the Windows "animation effects" accessibility switch
  const osReduced = matchMedia('(prefers-reduced-motion: reduce)').matches
  el.dataset.motion = s.animations === 'full' && osReduced ? 'reduced' : s.animations
  // "Off" means off: every Motion animation (springs included) jumps to its end state
  MotionGlobalConfig.skipAnimations = s.animations === 'off'
  el.dataset.density = s.density
  el.dataset.material = s.nativeMaterial && api.platform.isWin11 ? 'native' : 'css'
  el.style.setProperty('--glass', String(s.glass / 100))
  el.style.setProperty('--ui-scale', String(s.uiScale / 100))
  el.lang = s.language
}

export function SettingsProvider({ children }: { children: ReactNode }) {
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS)
  useEffect(() => {
    api.settings.get().then((s) => { setSettings(s); applyToDocument(s) })
    const off = api.settings.onChanged((s) => { setSettings(s); applyToDocument(s) })
    const mq = matchMedia('(prefers-color-scheme: dark)')
    const re = () => setSettings((s) => { applyToDocument(s); return s })
    mq.addEventListener('change', re)
    return () => { off(); mq.removeEventListener('change', re) }
  }, [])
  const value = useMemo<SettingsCtx>(() => ({
    settings,
    update: async (p) => { const s = await api.settings.set(p); setSettings(s); applyToDocument(s) }
  }), [settings])
  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>
}

export const useSettings = () => useContext(SettingsContext)

// ------------------------------------------------------------------ monitor

export const HISTORY = 90   // samples kept per series

type SeriesKey = 'cpu' | 'gpu' | 'gpuTemp' | 'vram' | 'mem' | 'rx' | 'tx' | 'ping' | 'diskR' | 'diskW' | 'diskA'

class MonitorStore {
  info: MonitorInfo | null = null
  tick: MonitorTick | null = null
  series: Record<SeriesKey, number[]> = { cpu: [], gpu: [], gpuTemp: [], vram: [], mem: [], rx: [], tx: [], ping: [], diskR: [], diskW: [], diskA: [] }
  version = 0
  private subs = new Set<() => void>()

  constructor() {
    api.monitor.info().then((i) => { if (i) { this.info = i; this.bump() } })
    api.monitor.onInfo((i) => { this.info = i; this.bump() })
    api.monitor.onTick((t) => this.push(t))
  }

  private add(k: SeriesKey, v: number | null | undefined) {
    const a = this.series[k]
    a.push(v == null || !isFinite(v) ? (a.length ? a[a.length - 1] : 0) : v)
    if (a.length > HISTORY) a.shift()
  }

  private push(t: MonitorTick) {
    this.tick = t
    const g = t.gpus[0]
    const d = t.disks
    this.add('cpu', t.cpu.load)
    this.add('gpu', g?.load ?? 0)
    this.add('gpuTemp', g?.temp ?? null)
    this.add('vram', g && g.vramTotal ? ((g.vramUsed ?? 0) / g.vramTotal) * 100 : 0)
    this.add('mem', t.mem.total ? (t.mem.used / t.mem.total) * 100 : 0)
    this.add('rx', t.net.rx)
    this.add('tx', t.net.tx)
    this.add('ping', t.net.ping)
    this.add('diskR', d.reduce((s, x) => s + x.read, 0))
    this.add('diskW', d.reduce((s, x) => s + x.write, 0))
    this.add('diskA', Math.max(0, ...d.map((x) => x.active ?? 0)))
    this.bump()
  }

  private bump() { this.version++; this.subs.forEach((f) => f()) }
  subscribe = (f: () => void) => { this.subs.add(f); return () => this.subs.delete(f) }
  getVersion = () => this.version
}

export const monitorStore = new MonitorStore()

/** Re-renders the caller on every new monitor sample. */
export function useMonitor() {
  useSyncExternalStore(monitorStore.subscribe, monitorStore.getVersion)
  return monitorStore
}
