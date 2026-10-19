import { app } from 'electron'
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { DEFAULT_SETTINGS, type DeepPartial, type Settings } from '@shared/types'

const file = () => join(app.getPath('userData'), 'settings.json')

function isObj(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

/** Deep merge that only accepts keys/types that exist in the defaults. */
function merge<T>(base: T, patch: unknown): T {
  if (!isObj(base) || !isObj(patch)) return base
  const out: Record<string, unknown> = { ...(base as Record<string, unknown>) }
  for (const [k, v] of Object.entries(patch)) {
    if (!(k in out)) continue
    const cur = out[k]
    if (isObj(cur)) out[k] = merge(cur, v)
    else if (typeof v === typeof cur) out[k] = v
  }
  return out as T
}

function sanitize(s: Settings): Settings {
  const clamp = (n: number, a: number, b: number) => Math.min(b, Math.max(a, Math.round(n)))
  s.glass = clamp(s.glass, 0, 100)
  s.uiScale = clamp(s.uiScale, 90, 125)
  if (![500, 1000, 2000].includes(s.refreshMs)) s.refreshMs = 1000
  if (![0, 5, 15, 30].includes(s.security.autoLockMinutes)) s.security.autoLockMinutes = 0
  if (!['en', 'it', 'es', 'fr', 'de'].includes(s.language)) s.language = 'en'
  // ping target: hostname or IPv4/IPv6 only
  if (!/^[a-zA-Z0-9.\-:]{1,253}$/.test(s.pingHost)) s.pingHost = '1.1.1.1'
  for (const k of ['gpuTemp', 'cpuLoad', 'ramLoad', 'ping'] as const) s.notifications[k] = clamp(s.notifications[k], 0, 1000)
  return s
}

let current: Settings | null = null

export function loadSettings(): Settings {
  if (current) return current
  let raw: unknown = {}
  try { if (existsSync(file())) raw = JSON.parse(readFileSync(file(), 'utf8')) } catch { raw = {} }
  current = sanitize(merge(structuredClone(DEFAULT_SETTINGS), raw))
  return current
}

export function saveSettings(patch: DeepPartial<Settings>): Settings {
  const next = sanitize(merge(structuredClone(loadSettings()), patch))
  current = next
  try {
    mkdirSync(dirname(file()), { recursive: true })
    const tmp = file() + '.tmp'
    writeFileSync(tmp, JSON.stringify(next, null, 2), 'utf8')
    renameSync(tmp, file())   // atomic replace: never a half-written settings file
  } catch { /* keep in memory */ }
  return next
}
