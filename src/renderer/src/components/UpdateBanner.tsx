import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useState } from 'react'
import { Download, Loader2, X } from 'lucide-react'
import type { UpdateStatus } from '@shared/types'
import { api } from '@/lib/api'
import { spring } from '@/lib/motion'
import { useT } from '@/i18n'

// Floating notice in the corner: shows download progress and, once the update
// is downloaded, offers a restart. "Later" hides it until the next version.
export function UpdateBanner() {
  const t = useT()
  const [u, setU] = useState<UpdateStatus>({ state: 'idle' })
  const [dismissed, setDismissed] = useState('')
  useEffect(() => { api.app.updateStatus().then(setU).catch(() => {}); return api.app.onUpdate(setU) }, [])

  const show = (u.state === 'ready' || u.state === 'downloading') && dismissed !== `${u.state}:${u.version ?? ''}`
  return (
    <AnimatePresence>
      {show && (
        <motion.div className="update-banner glass strong rim" role="status"
          initial={{ opacity: 0, y: 16, scale: 0.97 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={{ opacity: 0, y: 10, scale: 0.98 }} transition={spring.smooth}>
          <span className="ub-ico">{u.state === 'ready' ? <Download size={16} /> : <Loader2 size={16} className="spin" />}</span>
          <div className="ub-text">
            {u.state === 'ready' ? t('upd.ready', { v: u.version ?? '' }) : t('upd.downloading', { v: u.version ?? '', p: u.percent ?? 0 })}
            {u.state === 'downloading' && <div className="ub-bar"><motion.div initial={false} animate={{ width: `${u.percent ?? 0}%` }} transition={spring.smooth} /></div>}
          </div>
          {u.state === 'ready' && <button className="btn primary sm" onClick={() => api.app.installUpdate()}>{t('upd.restart')}</button>}
          <button className="btn ghost sm" aria-label={t('upd.later')} title={t('upd.later')} onClick={() => setDismissed(`${u.state}:${u.version ?? ''}`)}><X size={14} /></button>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
