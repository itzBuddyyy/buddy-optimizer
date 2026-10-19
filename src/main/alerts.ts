import { Notification } from 'electron'
import type { MonitorTick, Settings } from '@shared/types'
import { t } from './i18n'

/**
 * Threshold notifications. A metric must stay above its limit for a while
 * (no alert for a 1-second spike) and each alert has a cooldown so it never
 * spams during a gaming session.
 */
const SUSTAIN_MS = 10_000
const COOLDOWN_MS = 10 * 60_000

type Key = 'gpuTemp' | 'cpuLoad' | 'ramLoad' | 'ping'
const since: Partial<Record<Key, number>> = {}
const lastFired: Partial<Record<Key, number>> = {}

export function evaluateAlerts(tick: MonitorTick, s: Settings, icon: string) {
  if (!s.notifications.enabled || !Notification.isSupported()) return
  const n = s.notifications
  const gpuTemp = Math.max(...tick.gpus.map((g) => g.hotspot ?? g.temp ?? 0), 0)
  const values: Record<Key, { v: number | null; limit: number }> = {
    gpuTemp: { v: gpuTemp || null, limit: n.gpuTemp },
    cpuLoad: { v: tick.cpu.load, limit: n.cpuLoad },
    ramLoad: { v: tick.mem.load, limit: n.ramLoad },
    ping: { v: tick.net.pingAvg, limit: n.ping }
  }
  const now = Date.now()
  for (const key of Object.keys(values) as Key[]) {
    const { v, limit } = values[key]
    if (!limit || v == null || v < limit) { delete since[key]; continue }
    since[key] ??= now
    if (now - since[key]! < SUSTAIN_MS) continue
    if (lastFired[key] && now - lastFired[key]! < COOLDOWN_MS) continue
    lastFired[key] = now
    const shown = key === 'gpuTemp' && s.tempUnit === 'F' ? Math.round(v * 9 / 5 + 32) : Math.round(v)
    new Notification({
      title: t(s.language, `alert.${key}.title`),
      body: t(s.language, `alert.${key}.body`).replace('{v}', String(shown)).replace('{limit}', String(limit)),
      icon,
      silent: false
    }).show()
  }
}
