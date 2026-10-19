// End-to-end self-test of a built app.
//
//   set BUDDY_SMOKE_PW=<app password>
//   npm run build && npm run test:smoke                 (tests out/ with the dev Electron)
//   node scripts/smoke.mjs release/win-unpacked/BuddyOptimizer.exe   (tests a packaged build)
//
// The app types the password into its real lock screen, waits for live
// monitor data, screenshots every section and quits. This script then checks
// the results and fails (exit 1) on anything missing.
import { spawnSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const root = resolve(import.meta.dirname, '..')
const pw = process.env.BUDDY_SMOKE_PW
if (!pw) { console.error('Set BUDDY_SMOKE_PW to the app password first.'); process.exit(2) }

const target = process.argv[2]
const out = mkdtempSync(join(tmpdir(), 'buddy-smoke-'))
const env = { ...process.env, BUDDY_SMOKE_OUT: out, BUDDY_SMOKE_PW: pw }
const [cmd, args] = target ? [resolve(target), []] : [require('electron'), [root]]

console.log(`> running ${target ?? 'out/ (dev Electron)'}  -> ${out}`)
const r = spawnSync(cmd, args, { env, timeout: 120_000, stdio: 'ignore', windowsHide: false })
if (r.error) { console.error('failed to start:', r.error.message); process.exit(1) }

const fails = []
const check = (ok, msg) => { console.log(`${ok ? '  ✓' : '  ✗'} ${msg}`); if (!ok) fails.push(msg) }

const resFile = join(out, 'result.json')
check(existsSync(resFile), 'result.json written')
const res = existsSync(resFile) ? JSON.parse(readFileSync(resFile, 'utf8')) : {}
check(!res.error, `no error during run${res.error ? ': ' + res.error : ''}`)
check(res.unlocked === true, 'unlocked through the real lock screen')
check(res.monitorTick === 'yes', 'monitor helper delivered live samples')
check(typeof res.info?.cpu?.name === 'string' && res.info.cpu.name.length > 0, `hardware detected: ${res.info?.cpu?.name ?? '-'}`)
check(Array.isArray(res.info?.gpus) && res.info.gpus.length > 0, `GPU detected: ${res.info?.gpus?.[0]?.name ?? '-'}`)
check(typeof res.last?.cpu?.load === 'number', `CPU load sample: ${res.last?.cpu?.load}`)
check(res.fontOk === true, 'Inter font loaded (CSP allows bundled fonts)')
check(Array.isArray(res.consoleErrors) && res.consoleErrors.length === 0, `no console errors / CSP violations${res.consoleErrors?.length ? ':\n      ' + res.consoleErrors.join('\n      ') : ''}`)
check(typeof res.last?.mem?.used === 'number' && res.last.mem.used > 0, 'memory sample')
for (const s of ['1-lock', '2-dashboard', '3-optimize', '4-settings']) {
  const f = join(out, `${s}.png`)
  check(existsSync(f) && statSync(f).size > 20_000, `screenshot ${s}.png`)
}

console.log(fails.length ? `\nFAILED (${fails.length})` : '\nALL CHECKS PASSED')
process.exit(fails.length ? 1 : 0)
