// Selection lists exported/imported from the Apps and Tweaks screens
export const KEY_RE = /^[\w.+-]{1,100}$/

// Accepts Buddy's own export ({kind, keys}) and WinUtil exports (a flat key list, or the legacy object)
export function listFromJson(j: unknown, kind: 'apps' | 'tweaks'): string[] {
  const o = j as Record<string, unknown>
  const raw: unknown[] = Array.isArray(j) ? j : [...(Array.isArray(o?.keys) ? o.keys : []), ...(Array.isArray(o?.[kind === 'apps' ? 'WPFInstall' : 'WPFTweaks']) ? o[kind === 'apps' ? 'WPFInstall' : 'WPFTweaks'] as unknown[] : [])]
  const keys = raw.filter((k): k is string => typeof k === 'string').map((k) => (kind === 'apps' ? k.replace(/^WPFInstall/, '') : k)).filter((k) => KEY_RE.test(k))
  return [...new Set(keys)].slice(0, 2000)
}
