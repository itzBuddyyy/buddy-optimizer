import type { BuddyApi, MonitorInfo, MonitorTick, Settings } from '@shared/types'
import { DEFAULT_SETTINGS } from '@shared/types'

declare global { interface Window { buddy?: BuddyApi } }

/*
 * In the real app `window.buddy` comes from the preload script.
 * When the UI is opened in a plain browser (design preview), a simulated
 * backend with plausible data is used instead so every screen can be built
 * and reviewed without Electron. It is never used inside the packaged app.
 */
function createPreviewApi(): BuddyApi {
  let settings: Settings = structuredClone(DEFAULT_SETTINGS)
  const listeners: Record<string, Set<(v: any) => void>> = {}
  const emit = (ch: string, v?: unknown) => listeners[ch]?.forEach((f) => f(v))
  const on = (ch: string, f: (v: any) => void) => { (listeners[ch] ??= new Set()).add(f); return () => listeners[ch].delete(f) }

  const info: MonitorInfo = {
    cpu: { name: 'AMD Ryzen 7 7800X3D 8-Core Processor', vendor: 'AuthenticAMD', cores: 8, threads: 16, baseMhz: 4200 },
    gpus: [{ name: 'AMD Radeon RX 7800 XT', luid: '0x0_0x1', vendor: 'AMD', vram: 16 * 1024 ** 3, shared: 16 * 1024 ** 3 }],
    mem: { total: 32 * 1024 ** 3 },
    os: { name: 'Windows 11 Pro', version: '25H2', build: 26200, ubr: 9711 },
    board: { vendor: 'Micro-Star International Co., Ltd.', model: 'B650 GAMING PLUS WIFI (MS-7E26)', bios: '1.N2', system: 'MS-7E26' },
    disks: [{ index: 0, model: 'KINGSTON SNV2S1000G', letters: 'C:', size: 999e9, free: 222e9 }],
    computer: 'DESKTOP'
  }
  let phase = 0
  const wave = (base: number, amp: number, speed: number, noise = 0.3) => Math.max(0, base + Math.sin(phase * speed) * amp + (Math.random() - 0.5) * amp * noise)
  setInterval(() => {
    phase += 1
    const load = Math.min(100, wave(34, 22, 0.21))
    const gpuLoad = Math.min(100, wave(62, 30, 0.13))
    const tick: MonitorTick = {
      t: Date.now(),
      cpu: { load, cores: Array.from({ length: 16 }, (_, i) => Math.min(100, wave(load, 25, 0.3 + i * 0.07, 0.9))), mhz: 4800 + wave(150, 120, 0.4), mhzMax: null, temp: null, power: null, procs: 182, threads: 2950, ctx: 18000, uptime: 3600 * 5 + phase },
      gpus: [{ name: 'AMD Radeon RX 7800 XT', load: gpuLoad, load3d: gpuLoad, compute: 4, copy: 2, decode: 0, encode: 0, vramUsed: 6.2 * 1024 ** 3 + wave(0, 4e8, 0.1), vramTotal: 16 * 1024 ** 3, sharedUsed: 9e8, temp: 52 + gpuLoad * 0.18, hotspot: 64 + gpuLoad * 0.24, memTemp: 60, clock: 1900 + gpuLoad * 6, memClock: 2438, fan: 900 + gpuLoad * 12, fanPct: 30 + gpuLoad * 0.3, power: 60 + gpuLoad * 1.9 }],
      mem: { total: 32 * 1024 ** 3, avail: 20 * 1024 ** 3, used: 12 * 1024 ** 3 + wave(0, 3e8, 0.05), load: 37, commit: 15e9, commitLimit: 36e9, cache: 2e8, standby: 4.1e9, pages: 0 },
      disks: [{ index: 0, label: 'C:', model: 'KINGSTON SNV2S1000G', read: wave(2e6, 8e6, 0.5, 1), write: wave(1e6, 3e6, 0.37, 1), active: wave(4, 6, 0.5, 1), size: 999e9, free: 222e9, temp: null }],
      net: { adapter: 'Realtek Gaming 2.5GbE Family Controller', rx: wave(3e5, 2.5e5, 0.6, 1), tx: wave(6e4, 4e4, 0.45, 1), link: 1000, rxAll: 0, txAll: 0, pingHost: '1.1.1.1', ping: Math.round(wave(21, 3, 0.8, 1)), pingAvg: 22, jitter: 1.4, loss: 0 },
      sensors: { ready: true, note: null, cpuTemp: false }
    }
    emit('tick', tick)
  }, 1000)

  const result = (ok = 8) => ({ id: 1, ok: true, error: null, data: null, stats: { ok, skip: 1, fail: 0, dry: 0 }, reboot: true, journal: null })

  return {
    platform: { version: 'preview', isWin11: true },
    auth: {
      // Design preview only: any non-empty password unlocks; "wrong" demos the error state.
      // The real app checks an scrypt hash in the main process.
      unlock: async (pw) => (pw && pw !== 'wrong' ? { ok: true } : { ok: false }),
      change: async () => ({ ok: true }),
      isOwner: async () => true,
      lock: async () => emit('locked'),
      onLocked: (cb) => on('locked', cb)
    },
    settings: {
      get: async () => settings,
      set: async (patch) => { settings = { ...settings, ...(patch as Settings), notifications: { ...settings.notifications, ...(patch as any).notifications }, security: { ...settings.security, ...(patch as any).security }, engine: { ...settings.engine, ...(patch as any).engine } }; emit('settings', settings); return settings },
      onChanged: (cb) => on('settings', cb)
    },
    monitor: { info: async () => info, onInfo: (cb) => on('info', cb), onTick: (cb) => on('tick', cb) },
    engine: {
      start: async () => { await new Promise((r) => setTimeout(r, 900)); return { ok: true, ready: { sys: {}, wmi: true, xboxDefault: false, backupDir: '', logDir: '' } } },
      status: async () => ({ running: false }),
      run: async (action) => {
        const lines = ['Restore point created', 'SystemResponsiveness = 10', 'Game Mode ON', 'Mouse acceleration disabled live', 'MSI mode: AMD Radeon RX 7800 XT', 'Nagle OFF on Ethernet', 'Telemetry tasks disabled', 'Temp: 916 MB freed']
        for (let i = 0; i < lines.length; i++) {
          await new Promise((r) => setTimeout(r, 380))
          if (action === 'quick') emit('progress', { id: 1, step: ['restorePoint', 'power', 'gaming', 'services', 'privacy', 'cleanup'][Math.min(5, Math.floor(i * 6 / lines.length))], index: Math.min(6, Math.floor(i * 6 / lines.length) + 1), total: 6 })
          emit('log', { id: 1, level: i === 0 ? 'head' : 'ok', text: lines[i] })
        }
        return result()
      },
      query: async (what: string) => {
        if (what === 'toggles') return [
          { id: 'HAGS', label: 'Hardware-accelerated GPU scheduling', on: true, info: 'ON lowers latency on modern GPUs and is required for frame generation.' },
          { id: 'MPO', label: 'Disable Multi-Plane Overlay (MPO)', on: false, info: 'Fixes flicker on some multi-monitor setups.' },
          { id: 'HVCI', label: 'Memory Integrity (Core Isolation)', on: false, info: 'OFF gives some FPS but lowers security.' },
          { id: 'SVCSPLIT', label: 'Separate svchost per service (Windows default)', on: true, info: 'Keep ON.' }
        ] as any
        if (what === 'debloat') return [
          { Label: 'Clipchamp', Recommended: true, Installed: true }, { Label: 'Microsoft News', Recommended: true, Installed: true },
          { Label: 'Calculator', Recommended: false, Installed: true, Note: 'useful' }, { Label: 'OneDrive', Recommended: false, Installed: true, Note: 'checks your folders first' }
        ] as any
        if (what === 'startup') return [
          { name: 'Stream Deck', approved: 'x', where: 'HKCU Run', command: '', enabled: true },
          { name: 'GalaxyClient', approved: 'x', where: 'HKCU Run', command: '', enabled: true },
          { name: 'RtkAudUService', approved: 'y', where: 'HKLM Run', command: '', enabled: true }
        ] as any
        if (what === 'sessions') return [{ File: 'session-20261019-022258.json', Date: '2026-10-19T02:26:09', Changes: 214, Undone: false }] as any
        if (what === 'timer') return { installed: false, state: null } as any
        if (what === 'games') return [
          { id: 'cod', detected: true, running: false, configs: [{ name: 's.1.0.cod25.txt0', label: 'Warzone / Black Ops 7', folder: 'players', modified: '' }, { name: 's.1.1.bt.cod26.txt', label: 'Modern Warfare 4 Beta', folder: 'players', modified: '' }], exes: [], lastBackup: '2026-10-19T02:26:09', multiGpu: false },
          { id: 'fortnite', detected: true, running: false, configs: [{ name: 'GameUserSettings.ini', label: 'Fortnite', folder: 'WindowsClient', modified: '' }], exes: [], lastBackup: null, multiGpu: false },
          { id: 'apex', detected: true, running: true, configs: [{ name: 'videoconfig.txt', label: 'Apex Legends', folder: 'local', modified: '' }], exes: [], lastBackup: null, multiGpu: false },
          { id: 'valorant', detected: false, running: false, configs: [], exes: [], lastBackup: null, multiGpu: false }
        ] as any
        return [] as any
      },
      onLog: (cb) => on('log', cb),
      onProgress: (cb) => on('progress', cb),
      onExit: (cb) => on('exit', cb)
    },
    win: { minimize() {}, maximize() {}, close() {}, onMaximized: () => () => {} },
    app: { openExternal() {}, openLogs() {}, copyText(text) { navigator.clipboard?.writeText(text).catch(() => {}) }, relaunch() {}, reboot: async () => {}, checkUpdates: async () => {}, installUpdate() {}, onUpdate: () => () => {}, testNotification() {} }
  }
}

export const api: BuddyApi = window.buddy ?? createPreviewApi()
export const isPreview = !window.buddy
