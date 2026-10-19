import { app } from 'electron'
import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

/*
 * App lock. The password is never stored in plain text: only an scrypt hash.
 * The default password's hash is below; once the user changes it, the new
 * salt+hash live in %APPDATA%\Buddy Optimizer\auth.json.
 *
 * Note: this is an access lock for the UI, not encryption. Anyone with admin
 * rights on the PC can still change Windows settings directly.
 */
const DEFAULT = {
  salt: 'ssHDPGSsRWBQR80OLA/3jA==',
  hash: 'eWeKXiIpNUbozH0geMbbnKwCN+ZmPfS9uSPfEyiISMMbn6I1dKpYGi9IlPllvmr844XLRlvpcaXO2IUYllSeGA=='
}
const PARAMS = { N: 32768, r: 8, p: 1, maxmem: 64 * 1024 * 1024 }

const file = () => join(app.getPath('userData'), 'auth.json')

function stored(): { salt: string; hash: string } {
  try {
    if (existsSync(file())) {
      const j = JSON.parse(readFileSync(file(), 'utf8'))
      if (typeof j.salt === 'string' && typeof j.hash === 'string') return j
    }
  } catch { /* fall back to default */ }
  return DEFAULT
}

// async scrypt: hashing takes ~100 ms and must not freeze the UI thread
const scryptAsync = (pw: string, salt: Buffer, len: number) =>
  new Promise<Buffer>((res, rej) => scrypt(pw, salt, len, PARAMS, (e, k) => (e ? rej(e) : res(k))))

async function check(password: string): Promise<boolean> {
  if (typeof password !== 'string' || password.length === 0 || password.length > 256) return false
  const s = stored()
  const expected = Buffer.from(s.hash, 'base64')
  const actual = await scryptAsync(password, Buffer.from(s.salt, 'base64'), expected.length)
  return timingSafeEqual(actual, expected)
}

// Brute-force brake: after 3 wrong tries each attempt waits longer (2s, 4s, 8s ... max 60s)
let failures = 0
let blockedUntil = 0
let unlocked = false
let checking = false

export function isUnlocked() { return unlocked }
export function lock() { unlocked = false }

export async function unlock(password: string): Promise<{ ok: boolean; waitMs?: number }> {
  const now = Date.now()
  if (now < blockedUntil) return { ok: false, waitMs: blockedUntil - now }
  if (checking) return { ok: false, waitMs: 500 }       // one attempt at a time (no parallel guessing)
  checking = true
  let good = false
  try { good = await check(password) } finally { checking = false }
  if (good) { failures = 0; unlocked = true; return { ok: true } }
  failures++
  if (failures >= 3) {
    const wait = Math.min(60_000, 1000 * 2 ** (failures - 2))
    blockedUntil = now + wait
    return { ok: false, waitMs: wait }
  }
  return { ok: false }
}

export async function changePassword(current: string, next: string): Promise<{ ok: boolean; error?: string }> {
  if (!unlocked) return { ok: false, error: 'locked' }
  if (!(await check(current))) return { ok: false, error: 'wrong' }
  if (typeof next !== 'string' || next.length < 6 || next.length > 128) return { ok: false, error: 'length' }
  const salt = randomBytes(16)
  const hash = await scryptAsync(next, salt, 64)
  writeFileSync(file(), JSON.stringify({ salt: salt.toString('base64'), hash: hash.toString('base64') }), 'utf8')
  return { ok: true }
}
