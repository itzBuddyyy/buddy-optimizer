import type { Transition, Variants } from 'motion/react'

// Spring presets tuned to feel like macOS / iOS system animations:
// quick to respond, slight settle, no wobble.
export const spring = {
  snappy: { type: 'spring', stiffness: 520, damping: 38, mass: 0.9 } as Transition,
  smooth: { type: 'spring', stiffness: 260, damping: 30, mass: 1 } as Transition,
  gentle: { type: 'spring', stiffness: 140, damping: 22, mass: 1 } as Transition,
  bouncy: { type: 'spring', stiffness: 400, damping: 22, mass: 0.8 } as Transition
}

/** Page enter/exit: rise + unblur, the way macOS reveals sheets and windows */
export const page: Variants = {
  initial: { opacity: 0, y: 14, filter: 'blur(8px)', scale: 0.995 },
  enter: { opacity: 1, y: 0, filter: 'blur(0px)', scale: 1, transition: { ...spring.smooth, staggerChildren: 0.045, delayChildren: 0.04 } },
  exit: { opacity: 0, y: -8, filter: 'blur(6px)', transition: { duration: 0.18, ease: [0.4, 0, 1, 1] } }
}

export const item: Variants = {
  initial: { opacity: 0, y: 16, scale: 0.985 },
  enter: { opacity: 1, y: 0, scale: 1, transition: spring.smooth }
}

export const pressable = {
  whileHover: { y: -2 },
  whileTap: { scale: 0.975 },
  transition: spring.snappy
}
