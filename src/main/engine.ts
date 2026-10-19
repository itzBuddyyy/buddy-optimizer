import { spawn } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { existsSync } from 'node:fs'
import { createServer, type Server, type Socket } from 'node:net'
import { resource } from './paths'
import type { EngineLog, EngineProgress, EngineReady, EngineResult } from '@shared/types'

/**
 * Bridge to the itzBuddy engine (PowerShell). The app itself runs WITHOUT
 * admin rights; when the user first runs an optimization we start
 * engine\Agent.ps1 elevated (one UAC prompt) and talk to it over a named pipe
 * whose name and one-time token are random per session, so no other process
 * can drive the elevated agent.
 */
export class Engine {
  private server: Server | null = null
  private sock: Socket | null = null
  private buf = ''
  private nextId = 1
  private pending = new Map<number, { resolve: (r: EngineResult) => void }>()
  private starting: Promise<{ ok: boolean; error?: string; ready?: EngineReady }> | null = null
  ready: EngineReady | null = null

  constructor(
    private onLog: (l: EngineLog) => void,
    private onProgress: (p: EngineProgress) => void,
    private onExit: () => void
  ) {}

  get running() { return !!this.sock && !!this.ready }

  start(): Promise<{ ok: boolean; error?: string; ready?: EngineReady }> {
    if (this.running) return Promise.resolve({ ok: true, ready: this.ready! })
    if (this.starting) return this.starting
    this.starting = this.doStart().finally(() => { this.starting = null })
    return this.starting
  }

  private doStart(): Promise<{ ok: boolean; error?: string; ready?: EngineReady }> {
    return new Promise((resolve) => {
      const agent = resource('engine', 'Agent.ps1')
      if (!existsSync(agent)) return resolve({ ok: false, error: 'engine-missing' })
      const pipeName = `buddy-optimizer-${randomBytes(12).toString('hex')}`
      const token = randomBytes(24).toString('hex')
      let settled = false
      const finish = (r: { ok: boolean; error?: string; ready?: EngineReady }) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        if (!r.ok) this.shutdown()
        resolve(r)
      }
      const timer = setTimeout(() => finish({ ok: false, error: 'timeout' }), 90_000)

      const server = createServer((sock) => {
        if (this.sock) { sock.destroy(); return }            // exactly one client
        this.sock = sock
        server.close()                                       // stop accepting further connections
        sock.setEncoding('utf8')
        sock.write(JSON.stringify({ token }) + '\n')
        sock.on('data', (chunk: string) => this.onData(chunk, finish))
        sock.on('close', () => {
          const wasReady = !!this.ready
          this.sock = null
          this.ready = null
          for (const [, p] of this.pending) p.resolve({ id: 0, ok: false, error: 'agent-closed', data: null, stats: { ok: 0, skip: 0, fail: 0, dry: 0 }, reboot: false, journal: null })
          this.pending.clear()
          finish({ ok: false, error: 'agent-closed' })
          if (wasReady) this.onExit()
        })
        sock.on('error', () => { /* handled by close */ })
      })
      this.server = server
      server.on('error', () => finish({ ok: false, error: 'pipe' }))
      server.listen(`\\\\.\\pipe\\${pipeName}`, () => {
        // Start-Process -Verb RunAs shows the UAC prompt; declining makes it throw (exit 1)
        const inner = `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "${agent}" -PipeName ${pipeName} -Token ${token}`
        const cmd = `try { Start-Process -FilePath powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList '${inner.replace(/'/g, "''")}' -ErrorAction Stop; exit 0 } catch { exit 1223 }`
        const launcher = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', cmd], { windowsHide: true })
        launcher.on('exit', (code) => { if (code !== 0) finish({ ok: false, error: code === 1223 ? 'uac-declined' : 'launch-failed' }) })
      })
    })
  }

  private onData(chunk: string, finish: (r: { ok: boolean; error?: string; ready?: EngineReady }) => void) {
    this.buf += chunk
    let nl: number
    while ((nl = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, nl).trim()
      this.buf = this.buf.slice(nl + 1)
      if (!line) continue
      let msg: any
      try { msg = JSON.parse(line) } catch { continue }
      switch (msg.type) {
        case 'ready': this.ready = msg; finish({ ok: true, ready: msg }); break
        case 'log': this.onLog(msg); break
        case 'progress': this.onProgress(msg); break
        case 'result': { const p = this.pending.get(msg.id); if (p) { this.pending.delete(msg.id); p.resolve(msg) } break }
      }
    }
  }

  private send(obj: Record<string, unknown>): Promise<EngineResult> {
    return new Promise((resolve) => {
      if (!this.sock) return resolve({ id: 0, ok: false, error: 'not-running', data: null, stats: { ok: 0, skip: 0, fail: 0, dry: 0 }, reboot: false, journal: null })
      const id = this.nextId++
      this.pending.set(id, { resolve })
      this.sock.write(JSON.stringify({ id, ...obj }) + '\n')
    })
  }

  run(action: string, args: Record<string, unknown>, dryRun: boolean, xboxMode: boolean | null) {
    return this.send({ cmd: 'run', action, args, dryRun, xboxMode })
  }

  async query(what: string) {
    const r = await this.send({ cmd: 'query', what, dryRun: false })
    if (!r.ok) throw new Error(r.error ?? 'query failed')
    return r.data
  }

  shutdown() {
    try { this.sock?.write(JSON.stringify({ id: 0, cmd: 'quit' }) + '\n') } catch { /* closed */ }
    try { this.sock?.end() } catch { /* closed */ }
    try { this.server?.close() } catch { /* closed */ }
    this.sock = null
    this.ready = null
  }
}
