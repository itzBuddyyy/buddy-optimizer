import { app } from 'electron'
import { join } from 'node:path'

/** Resolves bundled resources both in development and in the installed app. */
export function resource(...parts: string[]): string {
  if (app.isPackaged) return join(process.resourcesPath, ...parts)
  const root = join(__dirname, '..', '..')
  const devMap: Record<string, string> = { monitor: 'build-native/monitor', engine: 'engine', icons: 'build' }
  const [first, ...rest] = parts
  return join(root, devMap[first] ?? first, ...rest)
}
