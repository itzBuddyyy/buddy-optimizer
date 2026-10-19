import { motion } from 'motion/react'
import { Activity, Clock3, Cpu, Gauge, HardDrive, Info, MemoryStick, MonitorSmartphone, Network, Thermometer, Wifi, Zap, CircuitBoard } from 'lucide-react'
import { item, page } from '@/lib/motion'
import { useMonitor, useSettings } from '@/lib/store'
import { bits, bytes, duration, mhz, pct, rate, shortCpu, shortGpu, temp } from '@/lib/format'
import { Sparkline } from '@/components/Sparkline'
import { Ring } from '@/components/Ring'
import { AnimatedNumber } from '@/components/AnimatedNumber'
import { Meter } from '@/components/Controls'
import { useT } from '@/i18n'
import type { ReactNode } from 'react'

function Panel({ icon, title, sub, right, span, children }: { icon: ReactNode; title: string; sub?: string; right?: ReactNode; span: number; children: ReactNode }) {
  return (
    <motion.section variants={item} className="panel glass rim" style={{ gridColumn: `span ${span}` }}>
      <div className="panel-head">
        <div className="panel-title">
          <span className="ico">{icon}</span>
          <div>
            <h3>{title}</h3>
            {sub && <div className="sub" title={sub}>{sub}</div>}
          </div>
        </div>
        {right}
      </div>
      {children}
    </motion.section>
  )
}

function Stat({ k, v, hint }: { k: string; v: ReactNode; hint?: string }) {
  return (
    <div className="stat" title={hint}>
      <div className="k">{k}</div>
      <div className="v num">{v}</div>
    </div>
  )
}

const tone = (v: number | null | undefined, warn: number, bad: number) => (v == null ? 'accent' : v >= bad ? 'bad' : v >= warn ? 'warn' : 'accent') as 'accent' | 'warn' | 'bad'

export function Dashboard() {
  const t = useT()
  const m = useMonitor()
  const { settings } = useSettings()
  const info = m.info
  const tk = m.tick
  const anim = settings.animations !== 'off'
  const unit = settings.tempUnit
  const g = tk?.gpus[0]
  const gi = info?.gpus[0]

  const hour = new Date().getHours()
  const greet = hour < 12 ? t('dash.greetMorning') : hour < 18 ? t('dash.greetAfternoon') : t('dash.greetEvening')
  const headroom = tk ? Math.max(0, 100 - Math.max(tk.cpu.load ?? 0, g?.load ?? 0, tk.mem.load ?? 0)) : 0
  const memUsedPct = tk ? (tk.mem.used / tk.mem.total) * 100 : 0
  const vramPct = g && g.vramTotal ? ((g.vramUsed ?? 0) / g.vramTotal) * 100 : 0

  return (
    <motion.div variants={page} initial="initial" animate="enter" exit="exit">
      {/* ---------- hero */}
      <motion.section variants={item} className="hero glass strong rim">
        <div>
          <div className="faint" style={{ fontSize: 13, fontWeight: 600 }}>{greet}</div>
          <h1>{t('dash.title')}</h1>
          <div className="specs">
            {info ? (
              <>
                <span className="spec"><Cpu size={14} />{shortCpu(info.cpu.name)} · {info.cpu.cores}C/{info.cpu.threads}T</span>
                {gi && <span className="spec"><MonitorSmartphone size={14} />{shortGpu(gi.name)} · {bytes(gi.vram, 0)}</span>}
                <span className="spec"><MemoryStick size={14} />{bytes(info.mem.installed ?? info.mem.total, 0)} RAM</span>
                <span className="spec"><CircuitBoard size={14} />{info.board.model || info.board.system}</span>
                <span className="spec"><Info size={14} />{info.os.name} {info.os.version}</span>
              </>
            ) : <span className="spec">{t('m.waiting')}</span>}
          </div>
        </div>
        <div className="score">
          <Ring value={headroom} size={92} stroke={9} tone={headroom < 15 ? 'bad' : headroom < 35 ? 'warn' : 'accent'}>
            <div><div style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-.03em' }}><AnimatedNumber value={headroom} /></div><div className="faint" style={{ fontSize: 10, fontWeight: 600 }}>%</div></div>
          </Ring>
          <div>
            <div className="lbl">{t('dash.headroom')}</div>
            <div className="val">{headroom >= 50 ? t('dash.headroomGood') : headroom >= 20 ? t('dash.headroomBusy') : t('dash.headroomFull')}</div>
            <div className="faint" style={{ fontSize: 12, marginTop: 6 }}><Clock3 size={12} style={{ verticalAlign: -2 }} /> {t('m.uptime')} {tk ? duration(tk.cpu.uptime) : '—'}</div>
          </div>
        </div>
      </motion.section>

      <div className="grid">
        {/* ---------- CPU */}
        <Panel span={6} icon={<Cpu size={16} />} title={t('dash.cpu')} sub={info?.cpu.name}
          right={<span className="tag accent num">{mhz(tk?.cpu.mhz)}</span>}>
          <div className="row" style={{ gap: 22, alignItems: 'center' }}>
            <Ring value={tk?.cpu.load ?? 0} tone={tone(tk?.cpu.load, 75, 92)}>
              <div className="big" style={{ fontSize: 30 }}><AnimatedNumber value={tk?.cpu.load ?? null} /><small>%</small></div>
            </Ring>
            <div className="stats" style={{ flex: 1 }}>
              <Stat k={t('m.clock')} v={mhz(tk?.cpu.mhz)} />
              <Stat k={t('m.temp')} v={temp(tk?.cpu.temp, unit)} hint={tk && tk.cpu.temp == null ? t('m.cpuTempHint') : undefined} />
              <Stat k={t('m.power')} v={tk?.cpu.power ? `${Math.round(tk.cpu.power)} W` : '—'} hint={tk && tk.cpu.power == null ? t('m.cpuTempHint') : undefined} />
              <Stat k={t('m.processes')} v={tk?.cpu.procs ?? '—'} />
              <Stat k={t('m.threads')} v={tk?.cpu.threads?.toLocaleString() ?? '—'} />
              <Stat k={t('m.cores')} v={info ? `${info.cpu.cores} / ${info.cpu.threads}` : '—'} />
            </div>
          </div>
          <div style={{ marginTop: 16 }}>
            <Sparkline data={m.series.cpu} max={100} height={58} animate={anim} version={m.version} />
          </div>
          <div className="cores" style={{ marginTop: 10 }}>
            {(tk?.cpu.cores ?? Array.from({ length: info?.cpu.threads ?? 16 }, () => 0)).map((c, i) => (
              <div className="core" key={i} title={`#${i}: ${c.toFixed(0)}%`}><i style={{ height: `${Math.max(4, c)}%` }} /></div>
            ))}
          </div>
        </Panel>

        {/* ---------- GPU */}
        <Panel span={6} icon={<MonitorSmartphone size={16} />} title={t('dash.gpu')} sub={g?.name ?? gi?.name}
          right={<span className={`tag ${tone(g?.hotspot ?? g?.temp, 85, 95) === 'accent' ? 'accent' : tone(g?.hotspot ?? g?.temp, 85, 95)}`}><Thermometer size={12} />{temp(g?.temp, unit)}</span>}>
          <div className="row" style={{ gap: 22, alignItems: 'center' }}>
            <Ring value={g?.load ?? 0} tone={tone(g?.load, 90, 99)}>
              <div className="big" style={{ fontSize: 30 }}><AnimatedNumber value={g?.load ?? null} /><small>%</small></div>
            </Ring>
            <div className="stats" style={{ flex: 1 }}>
              <Stat k={t('m.temp')} v={temp(g?.temp, unit)} />
              <Stat k={t('m.hotspot')} v={temp(g?.hotspot, unit)} />
              <Stat k={t('m.memTemp')} v={temp(g?.memTemp, unit)} />
              <Stat k={t('m.clock')} v={mhz(g?.clock)} />
              <Stat k={t('m.fan')} v={g?.fan != null ? `${Math.round(g.fan)} rpm` : '—'} />
              <Stat k={t('m.power')} v={g?.power != null ? `${Math.round(g.power)} W` : '—'} />
            </div>
          </div>
          <div style={{ marginTop: 16 }}>
            <Sparkline data={m.series.gpu} max={100} height={58} animate={anim} version={m.version} color={['#7c4dff', '#ff8fc8']} />
          </div>
          <div style={{ marginTop: 12 }}>
            <div className="spread" style={{ fontSize: 12, marginBottom: 6 }}>
              <span className="faint" style={{ fontWeight: 600 }}>{t('m.vram')}</span>
              <span className="num muted">{bytes(g?.vramUsed)} / {bytes(g?.vramTotal ?? gi?.vram, 0)}</span>
            </div>
            <Meter value={vramPct} tone={tone(vramPct, 85, 95)} />
            <div className="stats" style={{ marginTop: 12, gridTemplateColumns: 'repeat(4, 1fr)' }}>
              <Stat k={t('m.engine3d')} v={pct(g?.load3d)} />
              <Stat k={t('m.compute')} v={pct(g?.compute)} />
              <Stat k={t('m.encode')} v={pct(g?.encode)} />
              <Stat k={t('m.decode')} v={pct(g?.decode)} />
            </div>
          </div>
        </Panel>

        {/* ---------- Memory */}
        <Panel span={4} icon={<MemoryStick size={16} />} title={t('dash.memory')} sub={info ? `${bytes(info.mem.installed ?? info.mem.total, 0)} · ${(info.mem.total / 1024 ** 3).toFixed(1)} GB ${t('m.usable')}` : undefined}
          right={<span className="tag num">{pct(memUsedPct)}</span>}>
          <div className="big num">{tk ? (tk.mem.used / 1024 ** 3).toFixed(1) : '—'}<small> / {tk ? (tk.mem.total / 1024 ** 3).toFixed(1) : '—'} GB</small></div>
          <div style={{ marginTop: 14 }}><Meter value={memUsedPct} tone={tone(memUsedPct, 80, 92)} height={8} /></div>
          <div style={{ marginTop: 14 }}>
            <Sparkline data={m.series.mem} max={100} height={52} animate={anim} version={m.version} color={['#6d5dfc', '#b98cff']} />
          </div>
          <div className="stats" style={{ marginTop: 14 }}>
            <Stat k={t('m.used')} v={bytes(tk?.mem.used)} />
            <Stat k={t('m.available')} v={bytes(tk?.mem.avail)} />
            <Stat k={t('m.standby')} v={bytes(tk?.mem.standby)} />
            <Stat k={t('m.committed')} v={tk?.mem.commit ? `${bytes(tk.mem.commit, 0)}` : '—'} />
          </div>
        </Panel>

        {/* ---------- Storage */}
        <Panel span={4} icon={<HardDrive size={16} />} title={t('dash.storage')} sub={tk?.disks.map((d) => d.model).filter(Boolean).join(' · ') || info?.disks.map((d) => d.model).join(' · ')}
          right={<span className="tag num"><Activity size={12} />{pct(Math.max(0, ...(tk?.disks.map((d) => d.active ?? 0) ?? [0])))}</span>}>
          <div className="row" style={{ gap: 18 }}>
            <div><div className="faint" style={{ fontSize: 11, fontWeight: 650, textTransform: 'uppercase', letterSpacing: '.06em' }}>{t('m.read')}</div><div style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-.02em' }} className="num">{rate(m.series.diskR.at(-1))}</div></div>
            <div><div className="faint" style={{ fontSize: 11, fontWeight: 650, textTransform: 'uppercase', letterSpacing: '.06em' }}>{t('m.write')}</div><div style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-.02em' }} className="num">{rate(m.series.diskW.at(-1))}</div></div>
          </div>
          <div style={{ marginTop: 14 }}>
            <Sparkline data={m.series.diskR} data2={m.series.diskW} height={52} animate={anim} version={m.version} color={['#8f6bff', '#d58cff']} color2={['#56d9a8', '#7fb6ff']} />
          </div>
          <div className="col" style={{ marginTop: 12, gap: 12 }}>
            {(tk?.disks ?? []).map((d) => {
              const used = d.size && d.free != null ? ((d.size - d.free) / d.size) * 100 : 0
              return (
                <div key={d.index}>
                  <div className="spread" style={{ fontSize: 12, marginBottom: 6 }}>
                    <span style={{ fontWeight: 600 }}>{d.label}{d.temp ? <span className="faint"> · {temp(d.temp, unit)}</span> : null}</span>
                    <span className="num muted">{bytes(d.free, 0)} {t('m.free')} / {bytes(d.size, 0)}</span>
                  </div>
                  <Meter value={used} tone={tone(used, 85, 95)} />
                </div>
              )
            })}
          </div>
        </Panel>

        {/* ---------- Network */}
        <Panel span={4} icon={<Network size={16} />} title={t('dash.network')} sub={tk?.net.adapter ?? undefined}
          right={tk?.net.link ? <span className="tag num"><Wifi size={12} />{tk.net.link >= 1000 ? `${(tk.net.link / 1000).toFixed(1)} Gb/s` : `${tk.net.link} Mb/s`}</span> : undefined}>
          <div className="row" style={{ gap: 18, alignItems: 'flex-end' }}>
            <div>
              <div className="faint" style={{ fontSize: 11, fontWeight: 650, textTransform: 'uppercase', letterSpacing: '.06em' }}>{t('m.ping')}</div>
              <div className="big num" style={{ color: tk?.net.ping == null ? 'var(--bad)' : undefined }}>
                {tk?.net.ping != null ? <AnimatedNumber value={tk.net.ping} /> : '—'}<small>ms</small>
              </div>
            </div>
            <div className="col" style={{ gap: 2, marginLeft: 'auto', textAlign: 'right', fontSize: 12 }}>
              <span className="muted num">↓ {bits(tk?.net.rx)}</span>
              <span className="faint num">↑ {bits(tk?.net.tx)}</span>
            </div>
          </div>
          <div style={{ marginTop: 14 }}>
            <Sparkline data={m.series.rx} data2={m.series.tx} height={52} animate={anim} version={m.version} color={['#7c4dff', '#ef8fd8']} color2={['#56d9a8', '#7fb6ff']} />
          </div>
          <div className="stats" style={{ marginTop: 14 }}>
            <Stat k={t('m.jitter')} v={tk?.net.jitter != null ? `${tk.net.jitter.toFixed(1)} ms` : '—'} />
            <Stat k={t('m.loss')} v={pct(tk?.net.loss)} />
            <Stat k={t('m.avg')} v={tk?.net.pingAvg != null ? `${Math.round(tk.net.pingAvg)} ms` : '—'} />
            <Stat k={t('m.target')} v={<span style={{ fontSize: 13 }}>{tk?.net.pingHost ?? settings.pingHost}</span>} />
          </div>
        </Panel>
      </div>

      {tk && !tk.sensors.ready && (
        <motion.div variants={item} className="faint" style={{ fontSize: 12, margin: '14px 6px 0', display: 'flex', gap: 6, alignItems: 'center' }}>
          <Gauge size={13} />{t('m.waiting')}
        </motion.div>
      )}
      <motion.div variants={item} className="faint" style={{ fontSize: 11.5, margin: '16px 6px 0', display: 'flex', gap: 6, alignItems: 'center' }}>
        <Zap size={12} />{t('dash.footnote')}
      </motion.div>
    </motion.div>
  )
}
