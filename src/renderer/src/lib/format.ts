// Number formatting helpers (locale-aware, compact, never "NaN")

export function bytes(n: number | null | undefined, digits = 1): string {
  if (n == null || !isFinite(n)) return '—'
  const u = ['B', 'KB', 'MB', 'GB', 'TB']
  let i = 0
  let v = Math.abs(n)
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
  return `${v.toFixed(i === 0 ? 0 : v >= 100 ? 0 : digits)} ${u[i]}`
}

export function rate(n: number | null | undefined): string {
  if (n == null || !isFinite(n)) return '—'
  return bytes(n) + '/s'
}

/** Network throughput in bits, as ISPs and games show it */
export function bits(n: number | null | undefined): string {
  if (n == null || !isFinite(n)) return '—'
  const b = n * 8
  if (b >= 1e9) return `${(b / 1e9).toFixed(2)} Gb/s`
  if (b >= 1e6) return `${(b / 1e6).toFixed(b >= 1e8 ? 0 : 1)} Mb/s`
  if (b >= 1e3) return `${(b / 1e3).toFixed(0)} kb/s`
  return `${Math.round(b)} b/s`
}

export function pct(n: number | null | undefined, digits = 0): string {
  if (n == null || !isFinite(n)) return '—'
  return `${n.toFixed(digits)}%`
}

export function temp(c: number | null | undefined, unit: 'C' | 'F'): string {
  if (c == null || !isFinite(c) || c <= 0) return '—'
  return unit === 'F' ? `${Math.round(c * 9 / 5 + 32)}°F` : `${Math.round(c)}°C`
}

export function mhz(n: number | null | undefined): string {
  if (n == null || !isFinite(n) || n <= 0) return '—'
  return n >= 1000 ? `${(n / 1000).toFixed(2)} GHz` : `${Math.round(n)} MHz`
}

export function duration(sec: number): string {
  const d = Math.floor(sec / 86400)
  const h = Math.floor((sec % 86400) / 3600)
  const m = Math.floor((sec % 3600) / 60)
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

/** Shortens marketing names: "AMD Ryzen 7 7800X3D 8-Core Processor" -> "Ryzen 7 7800X3D" */
export function shortCpu(name: string): string {
  return name.replace(/\(R\)|\(TM\)|®|™/g, '').replace(/\s+\d+-Core Processor$/i, '').replace(/ Processor$/i, '')
    .replace(/^AMD |^Intel /i, '').replace(/\s+/g, ' ').trim()
}

export function shortGpu(name: string): string {
  return name.replace(/^NVIDIA |^AMD |^Intel\(R\) /i, '').replace(/\s+/g, ' ').trim()
}
