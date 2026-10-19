import { contextBridge, ipcRenderer, type IpcRendererEvent } from 'electron'
import type { BuddyApi } from '@shared/types'

// Minimal, typed bridge. The renderer never gets Node or raw ipcRenderer.
function on<T>(channel: string, cb: (v: T) => void) {
  const h = (_e: IpcRendererEvent, v: T) => cb(v)
  ipcRenderer.on(channel, h)
  return () => { ipcRenderer.removeListener(channel, h) }
}

const build = Number((process.getSystemVersion?.() ?? '10.0.0').split('.')[2] ?? 0)

const api: BuddyApi = {
  platform: { version: process.versions.electron, isWin11: build >= 22000 },
  auth: {
    unlock: (pw) => ipcRenderer.invoke('auth:unlock', pw),
    change: (cur, next) => ipcRenderer.invoke('auth:change', cur, next),
    isOwner: () => ipcRenderer.invoke('auth:isOwner'),
    lock: () => ipcRenderer.invoke('auth:lock'),
    onLocked: (cb) => on('auth:locked', cb)
  },
  settings: {
    get: () => ipcRenderer.invoke('settings:get'),
    set: (patch) => ipcRenderer.invoke('settings:set', patch),
    onChanged: (cb) => on('settings:changed', cb)
  },
  monitor: {
    info: () => ipcRenderer.invoke('monitor:info'),
    onInfo: (cb) => on('monitor:info', cb),
    onTick: (cb) => on('monitor:tick', cb)
  },
  engine: {
    start: () => ipcRenderer.invoke('engine:start'),
    status: () => ipcRenderer.invoke('engine:status'),
    run: (action, args, opts) => ipcRenderer.invoke('engine:run', action, args ?? {}, opts ?? {}),
    query: (what) => ipcRenderer.invoke('engine:query', what),
    onLog: (cb) => on('engine:log', cb),
    onProgress: (cb) => on('engine:progress', cb),
    onExit: (cb) => on('engine:exit', cb)
  },
  win: {
    minimize: () => ipcRenderer.send('win:minimize'),
    maximize: () => ipcRenderer.send('win:maximize'),
    close: () => ipcRenderer.send('win:close'),
    onMaximized: (cb) => on('win:maximized', cb)
  },
  app: {
    openExternal: (url) => ipcRenderer.send('app:openExternal', url),
    openLogs: () => ipcRenderer.send('app:openLogs'),
    copyText: (text) => ipcRenderer.send('app:copyText', text),
    relaunch: () => ipcRenderer.send('app:relaunch'),
    reboot: () => ipcRenderer.invoke('app:reboot'),
    checkUpdates: () => ipcRenderer.invoke('app:checkUpdates'),
    updateStatus: () => ipcRenderer.invoke('app:updateStatus'),
    installUpdate: () => ipcRenderer.send('app:installUpdate'),
    onUpdate: (cb) => on('update:status', cb),
    testNotification: () => ipcRenderer.send('app:testNotification')
  }
}

contextBridge.exposeInMainWorld('buddy', api)
