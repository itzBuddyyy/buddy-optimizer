import { AnimatePresence, motion } from 'motion/react'
import { createContext, useCallback, useContext, useState, type ReactNode } from 'react'
import { AlertTriangle, CheckCircle2, Info } from 'lucide-react'
import { spring } from '@/lib/motion'
import { useT } from '@/i18n'

// ------------------------------------------------------------------ toasts

type Tone = 'ok' | 'bad' | 'info'
interface Toast { id: number; tone: Tone; text: string }
const ToastCtx = createContext<(tone: Tone, text: string) => void>(() => {})
export const useToast = () => useContext(ToastCtx)

// ------------------------------------------------------------------ confirm sheet

interface ConfirmOpts { title: string; body: string; confirm: string; danger?: boolean }
const ConfirmCtx = createContext<(o: ConfirmOpts) => Promise<boolean>>(async () => false)
export const useConfirm = () => useContext(ConfirmCtx)

export function OverlayProvider({ children }: { children: ReactNode }) {
  const t = useT()
  const [toasts, setToasts] = useState<Toast[]>([])
  const [dialog, setDialog] = useState<(ConfirmOpts & { resolve: (v: boolean) => void }) | null>(null)

  const toast = useCallback((tone: Tone, text: string) => {
    const id = Date.now() + Math.random()
    setToasts((l) => [...l.slice(-3), { id, tone, text }])
    setTimeout(() => setToasts((l) => l.filter((x) => x.id !== id)), 4200)
  }, [])

  const confirm = useCallback((o: ConfirmOpts) => new Promise<boolean>((resolve) => setDialog({ ...o, resolve })), [])
  const close = (v: boolean) => { dialog?.resolve(v); setDialog(null) }

  return (
    <ToastCtx.Provider value={toast}>
      <ConfirmCtx.Provider value={confirm}>
        {children}
        <AnimatePresence>
          {dialog && (
            <motion.div className="scrim" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onMouseDown={(e) => e.target === e.currentTarget && close(false)}>
              <motion.div className="sheet glass strong rim" role="dialog" aria-modal="true"
                initial={{ opacity: 0, scale: 0.94, y: 12, filter: 'blur(6px)' }} animate={{ opacity: 1, scale: 1, y: 0, filter: 'blur(0px)' }}
                exit={{ opacity: 0, scale: 0.97, y: 6, transition: { duration: 0.14 } }} transition={spring.smooth}
                onKeyDown={(e) => { if (e.key === 'Escape') close(false) }}>
                <h3>{dialog.title}</h3>
                <p>{dialog.body}</p>
                <div className="actions">
                  <button className="btn" onClick={() => close(false)}>{t('common.cancel')}</button>
                  <button className={`btn ${dialog.danger ? 'danger' : 'primary'}`} autoFocus onClick={() => close(true)}>{dialog.confirm}</button>
                </div>
              </motion.div>
            </motion.div>
          )}
        </AnimatePresence>
        <div className="toasts">
          <AnimatePresence>
            {toasts.map((x) => (
              <motion.div key={x.id} className="toast glass strong rim" layout
                initial={{ opacity: 0, x: 40, scale: 0.96 }} animate={{ opacity: 1, x: 0, scale: 1 }} exit={{ opacity: 0, x: 30, scale: 0.97, transition: { duration: 0.16 } }}
                transition={spring.smooth}>
                <span className={`ti ${x.tone}`}>{x.tone === 'ok' ? <CheckCircle2 size={16} /> : x.tone === 'bad' ? <AlertTriangle size={16} /> : <Info size={16} />}</span>
                <span>{x.text}</span>
              </motion.div>
            ))}
          </AnimatePresence>
        </div>
      </ConfirmCtx.Provider>
    </ToastCtx.Provider>
  )
}
