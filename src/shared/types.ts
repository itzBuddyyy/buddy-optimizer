// Types shared by the main process, preload and renderer.

export type Language = 'en' | 'it' | 'es' | 'fr' | 'de'
export type Theme = 'dark' | 'light' | 'system'
export type Motion = 'full' | 'reduced' | 'off'

export interface Settings {
  language: Language
  launchAtStartup: boolean
  startMinimized: boolean
  closeToTray: boolean
  checkUpdates: boolean

  theme: Theme
  glass: number            // 0-100: blur / translucency strength
  windowControls: 'mac' | 'windows'
  density: 'comfortable' | 'compact'
  uiScale: number          // 90-125 (%)
  nativeMaterial: boolean  // Windows 11 acrylic behind the window

  animations: Motion

  hardwareAcceleration: boolean
  refreshMs: 500 | 1000 | 2000
  pauseWhenHidden: boolean
  tempUnit: 'C' | 'F'
  pingHost: string

  notifications: {
    enabled: boolean
    onComplete: boolean
    gpuTemp: number        // 0 = off
    cpuLoad: number
    ramLoad: number
    ping: number
  }

  security: {
    autoLockMinutes: 0 | 5 | 15 | 30
  }

  engine: {
    xboxMode: 'auto' | 'on' | 'off'
    dryRun: boolean
    restorePointFirst: boolean
  }
}

export const DEFAULT_SETTINGS: Settings = {
  language: 'en',
  launchAtStartup: false,
  startMinimized: false,
  closeToTray: true,
  checkUpdates: true,
  theme: 'dark',
  glass: 70,
  windowControls: 'mac',
  density: 'comfortable',
  uiScale: 100,
  nativeMaterial: false,
  animations: 'full',
  hardwareAcceleration: true,
  refreshMs: 1000,
  pauseWhenHidden: true,
  tempUnit: 'C',
  pingHost: '1.1.1.1',
  notifications: { enabled: true, onComplete: true, gpuTemp: 85, cpuLoad: 0, ramLoad: 90, ping: 0 },
  security: { autoLockMinutes: 0 },
  engine: { xboxMode: 'auto', dryRun: false, restorePointFirst: true }
}

// ---- monitor payloads (emitted by BuddyMonitor.exe) ----

export interface MonitorInfo {
  cpu: { name: string; vendor: string; cores: number; threads: number; baseMhz: number }
  gpus: { name: string; luid: string; vendor: string; vram: number; shared: number }[]
  mem: { total: number; installed?: number | null }
  os: { name: string; version: string; build: number; ubr: number }
  board: { vendor: string; model: string; bios: string; system: string }
  disks: { index: number; model: string; letters: string; size: number; free: number }[]
  computer: string
}

export interface GpuTick {
  name: string; load: number; load3d: number; compute: number; copy: number; decode: number; encode: number
  vramUsed: number | null; vramTotal: number; sharedUsed: number | null
  temp: number | null; hotspot: number | null; memTemp: number | null
  clock: number | null; memClock: number | null; fan: number | null; fanPct: number | null; power: number | null
}

export interface MonitorTick {
  t: number
  cpu: { load: number | null; cores: number[]; mhz: number | null; mhzMax: number | null; temp: number | null; power: number | null; procs: number | null; threads: number | null; ctx: number | null; uptime: number }
  gpus: GpuTick[]
  mem: { total: number; avail: number; used: number; load: number; commit: number | null; commitLimit: number | null; cache: number | null; standby: number | null; pages: number | null }
  disks: { index: number; label: string; model: string | null; read: number; write: number; active: number | null; size: number | null; free: number | null; temp: number | null }[]
  net: { adapter: string | null; rx: number; tx: number; link: number; rxAll: number; txAll: number; pingHost: string; ping: number | null; pingAvg: number | null; jitter: number | null; loss: number | null }
  sensors: { ready: boolean; note: string | null; cpuTemp: boolean }
}

// ---- engine ----

export type LogLevel = 'ok' | 'skip' | 'fail' | 'info' | 'warn' | 'head' | 'dry' | 'text'
export interface EngineLog { id: number; level: LogLevel; text: string }
export interface EngineProgress { id: number; step: string; index: number; total: number }
export interface EngineResult {
  id: number; ok: boolean; error: string | null; data: unknown
  stats: { ok: number; skip: number; fail: number; dry: number }
  reboot: boolean; journal: string | null
}
export interface EngineReady {
  sys: Record<string, unknown>; wmi: boolean; xboxDefault: boolean; backupDir: string; logDir: string
}

export interface UpdateStatus { state: 'idle' | 'checking' | 'available' | 'none' | 'downloading' | 'ready' | 'error'; version?: string; percent?: number; error?: string }

export interface BuddyApi {
  platform: { version: string; isWin11: boolean }
  auth: {
    unlock(password: string): Promise<{ ok: boolean; waitMs?: number }>
    change(current: string, next: string): Promise<{ ok: boolean; error?: string }>
    lock(): Promise<void>
    onLocked(cb: () => void): () => void
  }
  settings: {
    get(): Promise<Settings>
    set(patch: DeepPartial<Settings>): Promise<Settings>
    onChanged(cb: (s: Settings) => void): () => void
  }
  monitor: {
    info(): Promise<MonitorInfo | null>
    onInfo(cb: (i: MonitorInfo) => void): () => void
    onTick(cb: (t: MonitorTick) => void): () => void
  }
  engine: {
    start(): Promise<{ ok: boolean; error?: string; ready?: EngineReady }>
    status(): Promise<{ running: boolean; ready?: EngineReady }>
    run(action: string, args?: Record<string, unknown>, opts?: { dryRun?: boolean }): Promise<EngineResult>
    query<T = unknown>(what: string): Promise<T>
    onLog(cb: (l: EngineLog) => void): () => void
    onProgress(cb: (p: EngineProgress) => void): () => void
    onExit(cb: () => void): () => void
  }
  win: { minimize(): void; maximize(): void; close(): void; onMaximized(cb: (m: boolean) => void): () => void }
  app: {
    openExternal(url: string): void
    openLogs(): void
    relaunch(): void
    reboot(): Promise<void>
    checkUpdates(): Promise<void>
    installUpdate(): void
    onUpdate(cb: (u: UpdateStatus) => void): () => void
    testNotification(): void
  }
}

export type DeepPartial<T> = { [K in keyof T]?: T[K] extends object ? DeepPartial<T[K]> : T[K] }
