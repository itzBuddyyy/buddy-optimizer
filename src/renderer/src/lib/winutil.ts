import tweaksJson from '@winutil/config/tweaks.json'
import appsJson from '@winutil/config/applications.json'
import featureJson from '@winutil/config/feature.json'
import dnsJson from '@winutil/config/dns.json'
import appxJson from '@winutil/config/appx.json'
import presetJson from '@winutil/config/preset.json'
import cats from '@winutil/buddy-categories.json'

/*
 * WinUtil's catalogs (engine/winutil/config, MIT) regrouped into Buddy's own
 * categories. The engine applies entries by key, so only names and groups are
 * defined here.
 */

export interface WuTweak { key: string; name: string; desc: string; link?: string; toggle: boolean; caution: boolean; cat: TweakCat }
export interface WuApp { key: string; name: string; desc: string; link: string; cat: AppCat; foss: boolean; choco: boolean }
export interface WuAppx { key: string; name: string; desc: string; pkg: string }
export interface WuFeature { key: string; name: string; desc: string }

type Raw = Record<string, any>

// ---------------------------------------------------------------- tweaks

export const TWEAK_CATS = ['privacy', 'performance', 'cleanup', 'bloat', 'shell', 'appearance', 'network', 'system'] as const
export type TweakCat = (typeof TWEAK_CATS)[number]

const TWEAK_CAT = cats.tweaks as Record<string, TweakCat>

const tweaksRaw = tweaksJson as Raw
export const TWEAKS: WuTweak[] = Object.entries(tweaksRaw)
  .filter(([, v]) => v && (v.registry || v.service || v.InvokeScript || v.appx))
  .map(([key, v]) => ({
    key, name: v.Content, desc: v.Description ?? '', link: v.link, toggle: v.Type === 'Toggle',
    caution: String(v.category).startsWith('z__') || key === 'WPFTweaksDisableBitLocker', cat: TWEAK_CAT[key] ?? 'system'
  }))

// winutil's presets reference tweak keys; only keep ones that exist here
const presetRaw = presetJson as Record<string, string[]>
export const PRESETS: Record<'Minimal' | 'Standard' | 'Advanced', string[]> = {
  Minimal: presetRaw.Minimal.filter((k) => k in tweaksRaw),
  Standard: presetRaw.Standard.filter((k) => k in tweaksRaw),
  Advanced: presetRaw.Advanced.filter((k) => k in tweaksRaw)
}

export const DNS_PROVIDERS = ['Default', 'DHCP', 'Fastest', ...Object.keys(dnsJson as Raw)]

// ---------------------------------------------------------------- apps

export const APP_CATS = ['browsers', 'communication', 'gaming', 'hardware', 'security', 'network', 'media', 'office', 'development', 'microsoft', 'selfhosted', 'utilities'] as const
export type AppCat = (typeof APP_CATS)[number]

const FROM_WINUTIL = cats.appFromWinUtil as Record<string, AppCat>
// apps moved into Buddy's new categories
const MOVE = cats.appMoves as Partial<Record<AppCat, string[]>>
const moved = new Map<string, AppCat>(Object.entries(MOVE).flatMap(([c, ks]) => ks!.map((k) => [k, c as AppCat] as const)))

export const APPS: WuApp[] = Object.entries(appsJson as Raw)
  .map(([key, v]) => ({
    key, name: v.content, desc: v.description ?? '', link: v.link ?? '', foss: !!v.foss,
    choco: !!v.choco && v.choco !== 'na', cat: moved.get(key) ?? FROM_WINUTIL[v.category] ?? 'utilities'
  }))
  .sort((a, b) => a.name.localeCompare(b.name))

// ---------------------------------------------------------------- store apps, features, fixes

export const APPX: WuAppx[] = Object.entries(appxJson as Raw).map(([key, v]) => ({ key, name: v.Content, desc: v.Description ?? '', pkg: v.PackageId }))

const featureRaw = featureJson as Raw
export const FEATURES: WuFeature[] = Object.entries(featureRaw)
  .filter(([k, v]) => k.startsWith('WPFFeature') && k !== 'WPFFeatureInstall' && v.category === 'Features')
  .map(([key, v]) => ({ key, name: v.Content, desc: v.Description ?? '' }))

// Windows applets opened by the main process (whitelisted there)
export const PANELS = ['computer', 'control', 'mouse', 'network', 'power', 'printers', 'programs', 'region', 'security', 'sound', 'system', 'time', 'firewall', 'restore'] as const
export type Panel = (typeof PANELS)[number]
