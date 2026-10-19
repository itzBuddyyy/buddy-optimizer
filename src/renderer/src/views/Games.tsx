import { AnimatePresence, motion } from 'motion/react'
import { useState } from 'react'
import { ChevronDown, Copy, Crosshair, FileCog, History, Loader2, Mountain, Pickaxe, Play, RefreshCw, ShieldCheck, Target } from 'lucide-react'
import type { GameId, GameState } from '@shared/types'
import { item, page, spring } from '@/lib/motion'
import { useSettings } from '@/lib/store'
import { useEngine } from '@/lib/engine'
import { api } from '@/lib/api'
import { Switch } from '@/components/Controls'
import { useConfirm, useToast } from '@/components/Overlay'
import { useT, type TKey } from '@/i18n'
import { Loading, NeedsEngine, useQuery } from './OptimizeTabs'

type OptId = 'config' | 'clutter' | 'audio' | 'performanceMode' | 'readOnly' | 'gpuPref' | 'priority'

interface GameDef {
  id: GameId
  name: string
  icon: typeof Crosshair
  tint: [string, string]
  options: OptId[]
  defaults: Partial<Record<OptId, boolean>>
  configDesc: TKey
  tips: { text: TKey; code?: string }[]
}

// No publisher logos (trademarks): each game gets a tinted symbol instead.
const GAMES: GameDef[] = [
  {
    id: 'cod', name: 'Call of Duty', icon: Crosshair, tint: ['#f2b544', '#b5651d'],
    options: ['config', 'clutter', 'audio', 'gpuPref', 'priority'], defaults: { clutter: true, audio: false },
    configDesc: 'games.cod.config',
    tips: [{ text: 'games.cod.t1' }, { text: 'games.cod.t2' }, { text: 'games.cod.t3' }, { text: 'games.cod.t4' }]
  },
  {
    id: 'fortnite', name: 'Fortnite', icon: Pickaxe, tint: ['#5b9dff', '#9b5cff'],
    options: ['config', 'performanceMode', 'gpuPref', 'priority'], defaults: { performanceMode: true },
    configDesc: 'games.fortnite.config',
    tips: [{ text: 'games.fortnite.t1', code: '-FeatureLevelES31' }, { text: 'games.fortnite.t2' }, { text: 'games.fortnite.t3' }]
  },
  {
    id: 'apex', name: 'Apex Legends', icon: Mountain, tint: ['#ff5a4e', '#c2185b'],
    options: ['config', 'readOnly', 'gpuPref', 'priority'], defaults: { readOnly: false },
    configDesc: 'games.apex.config',
    tips: [{ text: 'games.apex.t1', code: '+fps_max 0' }, { text: 'games.apex.t2' }, { text: 'games.apex.t3' }]
  },
  {
    id: 'valorant', name: 'VALORANT', icon: Target, tint: ['#ff4655', '#8b1e3f'],
    options: ['config', 'gpuPref', 'priority'], defaults: {},
    configDesc: 'games.valorant.config',
    tips: [{ text: 'games.valorant.t1' }, { text: 'games.valorant.t2' }, { text: 'games.valorant.t3' }]
  }
]

const OPT_TEXT: Record<OptId, [TKey, TKey]> = {
  config: ['games.opt.config', 'games.opt.configD'],
  clutter: ['games.opt.clutter', 'games.opt.clutterD'],
  audio: ['games.opt.audio', 'games.opt.audioD'],
  performanceMode: ['games.opt.perf', 'games.opt.perfD'],
  readOnly: ['games.opt.readOnly', 'games.opt.readOnlyD'],
  gpuPref: ['games.opt.gpu', 'games.opt.gpuD'],
  priority: ['games.opt.prio', 'games.opt.prioD']
}

export function Games() {
  const t = useT()
  const { data, loading, reload } = useQuery<GameState[]>('games')
  const eng = useEngine()
  const byId = new Map((data ?? []).map((g) => [g.id, g]))
  return (
    <motion.div variants={page} initial="initial" animate="enter" exit="exit">
      <motion.div variants={item} className="page-head">
        <div>
          <h1>{t('games.title')}</h1>
          <p>{t('games.subtitle')}</p>
        </div>
        {eng.running && (
          <button className="btn sm" onClick={reload} disabled={loading || !!eng.busy}>
            <RefreshCw size={14} className={loading ? 'spin' : ''} />{t('games.scan')}
          </button>
        )}
      </motion.div>
      <motion.div variants={item}>
        <NeedsEngine>
          {!data && loading ? <Loading /> : (
            <div className="games">
              {GAMES.map((g) => <GameCard key={g.id} def={g} state={byId.get(g.id)} onChanged={reload} />)}
            </div>
          )}
        </NeedsEngine>
      </motion.div>
      <motion.div variants={item} className="faint games-note"><ShieldCheck size={13} />{t('games.note')}</motion.div>
    </motion.div>
  )
}

function GameCard({ def, state, onChanged }: { def: GameDef; state?: GameState; onChanged: () => void }) {
  const t = useT()
  const eng = useEngine()
  const toast = useToast()
  const confirm = useConfirm()
  const { settings } = useSettings()
  const dry = settings.engine.dryRun
  const [tips, setTips] = useState(false)
  const [opts, setOpts] = useState<Record<OptId, boolean>>(() => ({
    config: true, clutter: false, audio: false, performanceMode: false, readOnly: false, gpuPref: true, priority: false, ...def.defaults
  }))
  const Icon = def.icon
  const [busy, setBusy] = useState(false)
  const hasConfig = !!state?.configs.length
  const visible = def.options.filter((o) => o !== 'gpuPref' || state?.multiGpu)
  // the GPU switch is only shown on PCs with more than one GPU
  const effective = { ...opts, gpuPref: opts.gpuPref && !!state?.multiGpu }

  async function apply() {
    const ok = await confirm({
      title: t('games.confirmTitle', { g: def.name }),
      body: dry ? t('games.confirmDry', { g: def.name }) : t('games.confirmBody', { g: def.name }),
      confirm: dry ? t('opt.preview') : t('games.apply')
    })
    if (!ok) return
    await go('gameOptimize', { game: def.id, options: effective })
  }

  async function restore() {
    const ok = await confirm({ title: t('games.restoreTitle', { g: def.name }), body: t('games.restoreBody'), confirm: t('games.restore') })
    if (ok) await go('gameRestore', { game: def.id }, { dryRun: false })
  }

  async function go(action: string, args: Record<string, unknown>, o?: { dryRun?: boolean }) {
    setBusy(true)
    const res = await eng.run(action, args, o).finally(() => setBusy(false))
    if (!res) return
    if (!res.ok) toast('bad', `${t('opt.failed')}: ${res.error ?? ''}`)
    else if ((o?.dryRun ?? dry) && action === 'gameOptimize') toast('info', t('res.preview', { dry: res.stats.dry }))
    else toast(res.stats.fail ? 'bad' : 'ok', t('res.done', { ok: res.stats.ok, skip: res.stats.skip, fail: res.stats.fail }))
    onChanged()
  }

  const status = !state ? null
    : state.running ? <span className="tag warn">{t('games.running')}</span>
    : state.detected ? <span className="tag ok">{t('games.detected')}</span>
    : <span className="tag">{t('games.notFound')}</span>

  return (
    <motion.section className="game glass rim" whileHover={{ y: -2 }} transition={spring.snappy}
      style={{ ['--g1' as string]: def.tint[0], ['--g2' as string]: def.tint[1] }}>
      <div className="game-glow" aria-hidden />
      <div className="game-head">
        <span className="game-tile"><Icon size={22} strokeWidth={2} /></span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <h3>{def.name}</h3>
          <div className="faint" style={{ fontSize: 12 }}>
            {state?.lastBackup ? t('games.lastBackup', { d: new Date(state.lastBackup).toLocaleString() }) : t('games.noBackup')}
          </div>
        </div>
        {status}
      </div>

      <div className="game-files">
        {hasConfig ? state!.configs.map((c) => (
          <span key={`${c.folder}/${c.name}/${c.label}`} className="file-chip" title={`${c.folder}\\${c.name}`}>
            <FileCog size={12} />{c.label}<span className="faint">{c.name}</span>
          </span>
        )) : <span className="faint" style={{ fontSize: 12.5, lineHeight: 1.5 }}>{t('games.noConfig')}</span>}
      </div>

      <div className="game-opts">
        {visible.map((o) => (
          <label key={o} className="game-opt">
            <div className="txt">
              <div className="t">{t(OPT_TEXT[o][0])}</div>
              <div className="d">{o === 'config' ? t(def.configDesc) : t(OPT_TEXT[o][1])}</div>
            </div>
            <Switch checked={opts[o]} onChange={(v) => setOpts((s) => ({ ...s, [o]: v }))} />
          </label>
        ))}
      </div>

      <button className="btn ghost sm tips-toggle" onClick={() => setTips((s) => !s)} aria-expanded={tips}>
        {t('games.tips')}
        <ChevronDown size={14} style={{ transition: 'transform var(--dur-2) var(--spring)', transform: tips ? 'rotate(180deg)' : 'none' }} />
      </button>
      <AnimatePresence initial={false}>
        {tips && (
          <motion.ul className="game-tips" initial={{ height: 0, opacity: 0 }} animate={{ height: 'auto', opacity: 1 }} exit={{ height: 0, opacity: 0 }} transition={spring.smooth}>
            {def.tips.map((tip) => (
              <li key={tip.text}>
                <span>{t(tip.text)}</span>
                {tip.code && (
                  <span className="code-chip">
                    <code>{tip.code}</code>
                    <button className="btn ghost sm" aria-label={t('games.copy')} onClick={() => { api.app.copyText(tip.code!); toast('ok', t('games.copied')) }}><Copy size={12} /></button>
                  </span>
                )}
              </li>
            ))}
          </motion.ul>
        )}
      </AnimatePresence>

      <div className="foot">
        {state?.lastBackup
          ? <button className="btn sm" disabled={!!eng.busy || state.running} onClick={restore}><History size={14} />{t('games.restore')}</button>
          : <span />}
        <motion.button className="btn primary sm" whileTap={{ scale: 0.96 }} disabled={!!eng.busy || !state || state.running || (!hasConfig && !effective.gpuPref && !effective.priority)} onClick={apply}>
          {busy ? <Loader2 size={14} className="spin" /> : <Play size={13} fill="currentColor" />}{dry ? t('opt.preview') : t('games.apply')}
        </motion.button>
      </div>
    </motion.section>
  )
}
