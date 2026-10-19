import { app, BrowserWindow, ipcMain, Menu, nativeTheme, Notification, powerMonitor, session, shell, Tray } from 'electron'
import { spawn } from 'node:child_process'
import { join } from 'node:path'
import { loadSettings, saveSettings } from './settings'
import { changePassword, isUnlocked, lock, unlock } from './auth'
import { Monitor } from './monitor'
import { Engine } from './engine'
import { evaluateAlerts } from './alerts'
import { resource } from './paths'
import { t } from './i18n'
import type { DeepPartial, Settings, UpdateStatus } from '@shared/types'

const APP_ID = 'com.itzbuddy.buddyoptimizer'
const GITHUB_URL = 'https://github.com/itzBuddyyy/buddy-optimizer'

// ---- before ready: single instance + hardware acceleration ----
if (!app.requestSingleInstanceLock()) { app.quit(); process.exit(0) }
const boot = loadSettings()
if (!boot.hardwareAcceleration) app.disableHardwareAcceleration()
app.setAppUserModelId(APP_ID)

let win: BrowserWindow | null = null
let tray: Tray | null = null
let quitting = false
const iconPath = () => resource('icons', 'icon.ico')
const startHidden = process.argv.includes('--hidden')

// ---- monitor ----
const monitor = new Monitor(boot.refreshMs, boot.pingHost,
  (info) => send('monitor:info', info),
  (tick) => {
    const s = loadSettings()
    evaluateAlerts(tick, s, iconPath())
    if (!isUnlocked()) return
    if (s.pauseWhenHidden && (!win || !win.isVisible() || win.isMinimized())) return
    send('monitor:tick', tick)
  })

// ---- engine ----
const engine = new Engine(
  (l) => send('engine:log', l),
  (p) => send('engine:progress', p),
  () => send('engine:exit')
)

function send(channel: string, payload?: unknown) {
  if (win && !win.isDestroyed()) win.webContents.send(channel, payload)
}

function createWindow() {
  const s = loadSettings()
  const isWin11 = Number(process.getSystemVersion().split('.')[2] ?? 0) >= 22000
  const useMaterial = s.nativeMaterial && isWin11
  // window background matches the theme so there is no dark/light flash at startup
  const light = s.theme === 'light' || (s.theme === 'system' && !nativeTheme.shouldUseDarkColors)
  win = new BrowserWindow({
    width: 1320,
    height: 860,
    minWidth: 1080,
    minHeight: 700,
    show: false,
    // Native frame with the title bar hidden (no `frame: false`): keeps the
    // Windows 11 shadow, rounded corners, snap layouts and lets the acrylic
    // material render. Our own title bar + controls are drawn in the page.
    titleBarStyle: 'hidden',
    backgroundColor: useMaterial ? '#00000000' : light ? '#e9e1f3' : '#0b0612',
    ...(useMaterial ? { backgroundMaterial: 'acrylic' as const } : {}),
    icon: iconPath(),
    title: 'Buddy Optimizer',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webSecurity: true,
      spellcheck: false,
      devTools: !app.isPackaged
    }
  })

  // The UI is a single page: never navigate away or open new windows
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  win.webContents.on('will-navigate', (e) => e.preventDefault())
  win.webContents.on('will-attach-webview', (e) => e.preventDefault())

  win.on('ready-to-show', () => {
    if (!(startHidden || s.startMinimized)) win?.show()
  })
  win.on('maximize', () => send('win:maximized', true))
  win.on('unmaximize', () => send('win:maximized', false))
  win.on('close', (e) => {
    if (quitting) return
    if (loadSettings().closeToTray) { e.preventDefault(); win?.hide() }
    else quitting = true      // closing really quits when tray mode is off
  })

  if (process.env['ELECTRON_RENDERER_URL']) win.loadURL(process.env['ELECTRON_RENDERER_URL'])
  else win.loadFile(join(__dirname, '../renderer/index.html'))
  if (process.env['BUDDY_SMOKE_OUT']) runSmokeTest(win)
}

/*
 * Self-test used by CI / development: BUDDY_SMOKE_OUT=<folder> BUDDY_SMOKE_PW=<password>
 * Types the password into the real lock screen, waits for live monitor data,
 * saves screenshots of each section and quits. Needs the real password, so it
 * is not a way around the lock.
 */
function runSmokeTest(w: BrowserWindow) {
  const out = process.env['BUDDY_SMOKE_OUT']!
  const pw = process.env['BUDDY_SMOKE_PW'] ?? ''
  const fs = require('node:fs') as typeof import('node:fs')
  const shot = async (name: string) => fs.writeFileSync(join(out, `${name}.png`), (await w.webContents.capturePage()).toPNG())
  const js = (code: string) => w.webContents.executeJavaScript(code, true)
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms))
  const consoleErrors: string[] = []
  w.webContents.on('console-message', (e) => { if (e.level === 'error' || e.level === 'warning') consoleErrors.push(`[${e.level}] ${e.message}`) })
  w.webContents.on('render-process-gone', (_e, d) => consoleErrors.push(`[crash] ${d.reason}`))
  w.webContents.once('did-finish-load', async () => {
    try {
      w.show()
      await wait(2500)
      await shot('1-lock')
      await js(`(() => { const i = document.querySelector('input[type=password]'); const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set; set.call(i, ${JSON.stringify(pw)}); i.dispatchEvent(new Event('input', { bubbles: true })); i.form.requestSubmit(); })()`)
      await wait(9000)
      await shot('2-dashboard')
      const ticks = monitor.last ? 'yes' : 'no'
      await js(`window.dispatchEvent(new KeyboardEvent('keydown', { key: '2', ctrlKey: true }))`)
      await wait(2500)
      await shot('3-optimize')
      await js(`window.dispatchEvent(new KeyboardEvent('keydown', { key: '3', ctrlKey: true }))`)
      await wait(2500)
      await shot('4-settings')
      const fontOk = await js(`document.fonts.check('600 16px "Inter Variable"')`)
      fs.writeFileSync(join(out, 'result.json'), JSON.stringify({ unlocked: isUnlocked(), monitorTick: ticks, fontOk, consoleErrors, info: monitor.info, last: monitor.last }, null, 2))
    } catch (e) {
      fs.writeFileSync(join(out, 'result.json'), JSON.stringify({ error: String(e) }))
    }
    quitting = true
    app.quit()
  })
}

function showWindow() {
  if (!win) createWindow()
  if (win!.isMinimized()) win!.restore()
  win!.show()
  win!.focus()
}

function doLock() {
  lock()
  send('auth:locked')
}

function buildTray() {
  const s = loadSettings()
  if (!tray) {
    tray = new Tray(iconPath())
    tray.setToolTip('Buddy Optimizer')
    tray.on('click', showWindow)
  }
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: t(s.language, 'tray.open'), click: showWindow },
    { label: t(s.language, 'tray.lock'), click: doLock },
    { type: 'separator' },
    { label: t(s.language, 'tray.quit'), click: () => { quitting = true; app.quit() } }
  ]))
}

function applyLoginItem(s: Settings) {
  if (!app.isPackaged) return
  app.setLoginItemSettings({ openAtLogin: s.launchAtStartup, args: ['--hidden'] })
}

// ---- auto-lock on idle / screen lock ----
let idleTimer: NodeJS.Timeout | null = null
function scheduleIdleCheck() {
  if (idleTimer) clearInterval(idleTimer)
  idleTimer = setInterval(() => {
    const mins = loadSettings().security.autoLockMinutes
    if (mins > 0 && isUnlocked() && powerMonitor.getSystemIdleTime() >= mins * 60) doLock()
  }, 15_000)
}

// ---- updates (GitHub Releases) ----
async function checkUpdates(manual: boolean) {
  if (!app.isPackaged) { send('update:status', { state: 'none' } satisfies UpdateStatus); return }
  try {
    const { autoUpdater } = await import('electron-updater')
    autoUpdater.autoDownload = true
    autoUpdater.removeAllListeners()
    autoUpdater.on('checking-for-update', () => send('update:status', { state: 'checking' }))
    autoUpdater.on('update-available', (i) => send('update:status', { state: 'available', version: i.version }))
    autoUpdater.on('update-not-available', () => send('update:status', { state: 'none' }))
    autoUpdater.on('download-progress', (p) => send('update:status', { state: 'downloading', percent: Math.round(p.percent) }))
    autoUpdater.on('update-downloaded', (i) => send('update:status', { state: 'ready', version: i.version }))
    autoUpdater.on('error', (e) => send('update:status', { state: 'error', error: manual ? String(e?.message ?? e) : undefined }))
    await autoUpdater.checkForUpdates()
  } catch (e) {
    send('update:status', { state: 'error', error: manual ? String((e as Error).message) : undefined })
  }
}

// ---- IPC ----
function guard<T extends unknown[], R>(fn: (...a: T) => R) {
  // everything except unlock/settings-read requires the app to be unlocked
  return (_e: Electron.IpcMainInvokeEvent, ...a: T) => {
    if (!isUnlocked()) throw new Error('locked')
    return fn(...a)
  }
}

function registerIpc() {
  ipcMain.handle('auth:unlock', (_e, pw: string) => unlock(pw))
  ipcMain.handle('auth:change', guard((cur: string, next: string) => changePassword(cur, next)))
  ipcMain.handle('auth:lock', () => doLock())

  ipcMain.handle('settings:get', () => loadSettings())
  ipcMain.handle('settings:set', guard((patch: DeepPartial<Settings>) => {
    const before = loadSettings()
    const s = saveSettings(patch)
    if (s.refreshMs !== before.refreshMs) monitor.setInterval(s.refreshMs)
    if (s.pingHost !== before.pingHost) monitor.setPingHost(s.pingHost)
    if (s.launchAtStartup !== before.launchAtStartup) applyLoginItem(s)
    if (s.language !== before.language) buildTray()
    nativeTheme.themeSource = s.theme
    send('settings:changed', s)
    return s
  }))

  ipcMain.handle('monitor:info', () => monitor.info)

  ipcMain.handle('engine:start', guard(() => engine.start()))
  ipcMain.handle('engine:status', () => ({ running: engine.running, ready: engine.ready ?? undefined }))
  ipcMain.handle('engine:run', guard(async (action: string, args: Record<string, unknown> = {}, opts: { dryRun?: boolean } = {}) => {
    const s = loadSettings()
    if (!engine.running) {
      const r = await engine.start()
      if (!r.ok) return { id: 0, ok: false, error: r.error ?? 'engine', data: null, stats: { ok: 0, skip: 0, fail: 0, dry: 0 }, reboot: false, journal: null }
    }
    const xbox = s.engine.xboxMode === 'auto' ? null : s.engine.xboxMode === 'on'
    const dry = opts.dryRun ?? s.engine.dryRun
    if (action === 'quick' && !s.engine.restorePointFirst) args = { ...args, skipRestorePoint: true }
    const res = await engine.run(action, args, dry, xbox)
    const longRunning = ['quick', 'gaming', 'services', 'privacy', 'cleanup', 'debloat', 'ui', 'xboxFix'].includes(action)
    if (longRunning && !dry && s.notifications.enabled && s.notifications.onComplete && Notification.isSupported() && (!win?.isFocused())) {
      new Notification({
        title: t(s.language, 'done.title'),
        body: t(s.language, 'done.body').replace('{ok}', String(res.stats.ok)).replace('{fail}', String(res.stats.fail)) + (res.reboot ? ' ' + t(s.language, 'done.reboot') : ''),
        icon: iconPath()
      }).show()
    }
    return res
  }))
  ipcMain.handle('engine:query', guard((what: string) => engine.query(what)))

  ipcMain.on('win:minimize', () => win?.minimize())
  ipcMain.on('win:maximize', () => (win?.isMaximized() ? win.unmaximize() : win?.maximize()))
  ipcMain.on('win:close', () => win?.close())

  ipcMain.on('app:openExternal', (_e, url: string) => {
    // only known https destinations
    const allowed = [GITHUB_URL, 'https://www.amd.com/', 'https://www.nvidia.com/', 'https://www.intel.com/']
    if (typeof url === 'string' && allowed.some((a) => url.startsWith(a))) shell.openExternal(url)
  })
  ipcMain.on('app:openLogs', () => {
    if (!isUnlocked()) return
    shell.openPath(join(process.env.ProgramData ?? 'C:\\ProgramData', 'itzBuddy'))
  })
  ipcMain.on('app:relaunch', () => { quitting = true; app.relaunch(); app.exit(0) })
  ipcMain.handle('app:reboot', guard(() => {
    spawn('shutdown.exe', ['/r', '/t', '5', '/c', 'Buddy Optimizer: restarting to apply optimizations'], { windowsHide: true, detached: true })
  }))
  ipcMain.handle('app:checkUpdates', guard(() => checkUpdates(true)))
  ipcMain.on('app:installUpdate', async () => {
    if (!isUnlocked()) return
    const { autoUpdater } = await import('electron-updater')
    quitting = true
    autoUpdater.quitAndInstall()
  })
  ipcMain.on('app:testNotification', () => {
    const s = loadSettings()
    if (Notification.isSupported()) new Notification({ title: t(s.language, 'test.title'), body: t(s.language, 'test.body'), icon: iconPath() }).show()
  })
}

// ---- lifecycle ----
app.on('second-instance', showWindow)

app.whenReady().then(() => {
  const s = loadSettings()
  nativeTheme.themeSource = s.theme

  // Content-Security-Policy: production builds carry it as a <meta> tag in
  // index.html (file:// pages get no HTTP headers). In development the Vite
  // server needs inline scripts for hot reload, so it is relaxed there only.
  if (!app.isPackaged) {
    session.defaultSession.webRequest.onHeadersReceived((details, cb) => {
      cb({
        responseHeaders: {
          ...details.responseHeaders,
          'Content-Security-Policy': ["default-src 'self' http://localhost:*; script-src 'self' 'unsafe-inline' http://localhost:*; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src 'self' data:; connect-src 'self' ws://localhost:* http://localhost:*"]
        }
      })
    })
  }
  // No camera, microphone, notifications-from-web, etc. for the page itself
  session.defaultSession.setPermissionRequestHandler((_wc, _perm, cb) => cb(false))

  registerIpc()
  createWindow()
  buildTray()
  applyLoginItem(s)
  monitor.start()
  scheduleIdleCheck()
  powerMonitor.on('lock-screen', () => { if (loadSettings().security.autoLockMinutes > 0) doLock() })
  if (s.checkUpdates) setTimeout(() => checkUpdates(false), 8000)
})

app.on('before-quit', () => { quitting = true; monitor.stop(); engine.shutdown() })
app.on('window-all-closed', () => { if (quitting) app.quit() })
