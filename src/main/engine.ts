import { spawn } from 'node:child_process'
import { randomBytes, timingSafeEqual } from 'node:crypto'
import { existsSync } from 'node:fs'
import { createServer, type Server, type Socket } from 'node:net'
import { homedir } from 'node:os'
import { app } from 'electron'
import { resource } from './paths'
import type { EngineLog, EngineProgress, EngineReady, EngineResult } from '@shared/types'

// The agent runs elevated (possibly as another admin account if the UAC prompt
// was answered with different credentials), so the signed-in user's folders
// are passed along for per-user data such as game settings files.
function userEnv() {
  return { userProfile: homedir(), localAppData: process.env.LOCALAPPDATA ?? '', documents: app.getPath('documents') }
}

/**
 * Bridge to the itzBuddy engine (PowerShell). The app itself runs WITHOUT
 * admin rights; when the user first runs an optimization we start
 * engine\Agent.ps1 elevated (one UAC prompt) and talk to it over a named pipe
 * whose name and one-time secrets are random per session. The agent proves
 * itself first and only then receives the app's token, and the pipe stays
 * reserved until the session ends; the agent also checks that the pipe server is
 * this process (by PID), so another process cannot take over the elevated agent.
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
      const token = randomBytes(24).toString('hex')   // app -> agent
      const proof = randomBytes(24).toString('hex')   // agent -> app
      let settled = false
      const finish = (r: { ok: boolean; error?: string; ready?: EngineReady }) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        if (!r.ok) this.shutdown()
        resolve(r)
      }
      const timer = setTimeout(() => finish({ ok: false, error: 'timeout' }), 90_000)

      // The pipe stays open (and its name reserved) for the whole session; only a
      // client that sends the agent's proof first is accepted and receives the token.
      const server = createServer((sock) => {
        if (this.sock) { sock.destroy(); return }            // one verified agent per session
        sock.setEncoding('utf8')
        sock.on('error', () => { /* handled by close */ })
        let pre = ''
        const authTimer = setTimeout(() => sock.destroy(), 10_000)
        const onHello = (chunk: string) => {
          pre += chunk
          const nl = pre.indexOf('\n')
          if (nl < 0) { if (pre.length > 4096) sock.destroy(); return }
          sock.off('data', onHello)
          clearTimeout(authTimer)
          let hello: { proof?: unknown } | null = null
          try { hello = JSON.parse(pre.slice(0, nl)) } catch { /* rejected below */ }
          const got = Buffer.from(typeof hello?.proof === 'string' ? hello.proof : '')
          if (this.sock || got.length !== proof.length || !timingSafeEqual(got, Buffer.from(proof))) { sock.destroy(); return }
          this.sock = sock
          sock.write(JSON.stringify({ token }) + '\n')
          sock.on('data', (c: string) => this.onData(c, finish))
          sock.on('close', () => {
            const wasReady = !!this.ready
            this.sock = null
            this.ready = null
            for (const [, p] of this.pending) p.resolve({ id: 0, ok: false, error: 'agent-closed', data: null, stats: { ok: 0, skip: 0, fail: 0, dry: 0 }, reboot: false, journal: null })
            this.pending.clear()
            try { server.close() } catch { /* already closed */ }
            finish({ ok: false, error: 'agent-closed' })
            if (wasReady) this.onExit()
          })
          if (nl + 1 < pre.length) this.onData(pre.slice(nl + 1), finish)
        }
        sock.on('data', onHello)
      })
      this.server = server
      server.on('error', () => finish({ ok: false, error: 'pipe' }))
      server.listen(`\\\\.\\pipe\\${pipeName}`, () => {
        // Start-Process -Verb RunAs shows the UAC prompt; declining makes it throw (exit 1)
        const inner = `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "${agent}" -PipeName ${pipeName} -Token ${token} -Proof ${proof} -AppPid ${process.pid}`
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
      this.sock.write(JSON.stringify({ id, ...obj, env: userEnv() }) + '\n')
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
