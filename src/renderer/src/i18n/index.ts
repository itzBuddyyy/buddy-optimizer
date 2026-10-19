import { useCallback } from 'react'
import { useSettings } from '@/lib/store'
import type { Language } from '@shared/types'
import en from './en'
import it from './it'
import es from './es'
import fr from './fr'
import de from './de'

export type Dict = Record<keyof typeof en, string>
const dicts: Record<Language, Partial<Dict>> = { en, it, es, fr, de }

export const LANGUAGES: { value: Language; label: string }[] = [
  { value: 'en', label: 'English' },
  { value: 'it', label: 'Italiano' },
  { value: 'es', label: 'Español' },
  { value: 'fr', label: 'Français' },
  { value: 'de', label: 'Deutsch' }
]

export function translate(lang: Language, key: keyof typeof en, vars?: Record<string, string | number>) {
  let s = dicts[lang]?.[key] ?? en[key] ?? key
  if (vars) for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(String(v))
  return s
}

export function useT() {
  const { settings } = useSettings()
  return useCallback((key: keyof typeof en, vars?: Record<string, string | number>) => translate(settings.language, key, vars), [settings.language])
}

export type TKey = keyof typeof en
