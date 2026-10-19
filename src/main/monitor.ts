import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process'
import { existsSync } from 'node:fs'
import { createInterface } from 'node:readline'
import { resource } from './paths'
import type { MonitorInfo, MonitorTick } from '@shared/types'

/**
 * Owns the BuddyMonitor.exe helper: starts it, parses its JSON lines and
 * restarts it with backoff if it ever exits. The helper runs as the normal
 * user (no UAC) and reads Windows performance counters directly.
 */
export class Monitor {
  private proc: ChildProcessWithoutNullStreams | null = null
  private restarts = 0
  private stopped = false
  info: MonitorInfo | null = null
  last: MonitorTick | null = null

  constructor(
    private interval: number,
    private pingHost: string,
    private onInfo: (i: MonitorInfo) => void,
    private onTick: (t: MonitorTick) => void
  ) {}

  start() {
    this.stopped = false
    const exe = resource('monitor', 'BuddyMonitor.exe')
    if (!existsSync(exe)) { console.error('monitor helper missing:', exe); return }
    const p = spawn(exe, ['--interval', String(this.interval), '--ping', this.pingHost], { windowsHide: true })
    this.proc = p
    const rl = createInterface({ input: p.stdout })
    rl.on('line', (line) => {
      if (!line.startsWith('{')) return
      try {
        const msg = JSON.parse(line)
        if (msg.type === 'info') { this.info = msg; this.onInfo(msg) }
        else if (msg.type === 'tick') { this.last = msg; this.onTick(msg); this.restarts = 0 }
      } catch { /* ignore partial line */ }
    })
    p.stderr.on('data', () => { /* helper never writes stderr in normal operation */ })
    p.on('exit', () => {
      this.proc = null
      if (this.stopped) return
      const delay = Math.min(30_000, 1000 * 2 ** this.restarts++)
      setTimeout(() => !this.stopped && this.start(), delay)
    })
  }

  private send(cmd: string) { try { this.proc?.stdin.write(cmd + '\n') } catch { /* restarting */ } }

  setInterval(ms: number) { this.interval = ms; this.send(`interval ${ms}`) }
  setPingHost(h: string) { this.pingHost = h; this.send(`ping ${h}`) }

  stop() {
    this.stopped = true
    if (this.proc) { this.send('quit'); const p = this.proc; setTimeout(() => { try { p.kill() } catch { /* gone */ } }, 800) }
  }
}
