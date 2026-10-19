import type { Language } from '@shared/types'

// Strings used by the main process (tray menu, notifications, dialogs).
const strings: Record<Language, Record<string, string>> = {
  en: {
    'tray.open': 'Open Buddy Optimizer', 'tray.lock': 'Lock', 'tray.quit': 'Quit',
    'alert.gpuTemp.title': 'GPU is running hot', 'alert.gpuTemp.body': 'GPU temperature at {v}° (limit {limit}°). Check airflow and fan curve.',
    'alert.cpuLoad.title': 'High CPU load', 'alert.cpuLoad.body': 'CPU has been at {v}% for a while (limit {limit}%).',
    'alert.ramLoad.title': 'Memory almost full', 'alert.ramLoad.body': 'RAM usage at {v}% (limit {limit}%). Close background apps.',
    'alert.ping.title': 'High latency', 'alert.ping.body': 'Average ping {v} ms (limit {limit} ms).',
    'done.title': 'Optimization finished', 'done.body': '{ok} changes applied, {fail} failed.', 'done.reboot': 'Restart your PC to apply everything.',
    'test.title': 'Notifications are on', 'test.body': 'This is how Buddy Optimizer alerts will look.',
    'update.title': 'Update ready', 'update.body': 'Buddy Optimizer {v} has been downloaded. Restart the app to install it.'
  },
  it: {
    'tray.open': 'Apri Buddy Optimizer', 'tray.lock': 'Blocca', 'tray.quit': 'Esci',
    'alert.gpuTemp.title': 'GPU molto calda', 'alert.gpuTemp.body': 'Temperatura GPU a {v}° (limite {limit}°). Controlla flusso d\'aria e curva ventole.',
    'alert.cpuLoad.title': 'Carico CPU elevato', 'alert.cpuLoad.body': 'La CPU è al {v}% da un po\' (limite {limit}%).',
    'alert.ramLoad.title': 'Memoria quasi piena', 'alert.ramLoad.body': 'RAM al {v}% (limite {limit}%). Chiudi le app in background.',
    'alert.ping.title': 'Latenza alta', 'alert.ping.body': 'Ping medio {v} ms (limite {limit} ms).',
    'done.title': 'Ottimizzazione completata', 'done.body': '{ok} modifiche applicate, {fail} non riuscite.', 'done.reboot': 'Riavvia il PC per applicare tutto.',
    'test.title': 'Notifiche attive', 'test.body': 'Così appariranno gli avvisi di Buddy Optimizer.',
    'update.title': 'Aggiornamento pronto', 'update.body': 'Buddy Optimizer {v} è stato scaricato. Riavvia l’app per installarlo.'
  },
  es: {
    'tray.open': 'Abrir Buddy Optimizer', 'tray.lock': 'Bloquear', 'tray.quit': 'Salir',
    'alert.gpuTemp.title': 'La GPU está muy caliente', 'alert.gpuTemp.body': 'Temperatura de la GPU: {v}° (límite {limit}°). Revisa el flujo de aire.',
    'alert.cpuLoad.title': 'Carga de CPU alta', 'alert.cpuLoad.body': 'La CPU lleva un rato al {v}% (límite {limit}%).',
    'alert.ramLoad.title': 'Memoria casi llena', 'alert.ramLoad.body': 'RAM al {v}% (límite {limit}%). Cierra apps en segundo plano.',
    'alert.ping.title': 'Latencia alta', 'alert.ping.body': 'Ping medio {v} ms (límite {limit} ms).',
    'done.title': 'Optimización terminada', 'done.body': '{ok} cambios aplicados, {fail} fallidos.', 'done.reboot': 'Reinicia el PC para aplicarlo todo.',
    'test.title': 'Notificaciones activadas', 'test.body': 'Así se verán los avisos de Buddy Optimizer.',
    'update.title': 'Actualización lista', 'update.body': 'Buddy Optimizer {v} se ha descargado. Reinicia la app para instalarla.'
  },
  fr: {
    'tray.open': 'Ouvrir Buddy Optimizer', 'tray.lock': 'Verrouiller', 'tray.quit': 'Quitter',
    'alert.gpuTemp.title': 'Le GPU chauffe', 'alert.gpuTemp.body': 'Température GPU : {v}° (limite {limit}°). Vérifiez la ventilation.',
    'alert.cpuLoad.title': 'Charge CPU élevée', 'alert.cpuLoad.body': 'Le CPU est à {v} % depuis un moment (limite {limit} %).',
    'alert.ramLoad.title': 'Mémoire presque pleine', 'alert.ramLoad.body': 'RAM à {v} % (limite {limit} %). Fermez les apps en arrière-plan.',
    'alert.ping.title': 'Latence élevée', 'alert.ping.body': 'Ping moyen {v} ms (limite {limit} ms).',
    'done.title': 'Optimisation terminée', 'done.body': '{ok} modifications appliquées, {fail} échecs.', 'done.reboot': 'Redémarrez le PC pour tout appliquer.',
    'test.title': 'Notifications activées', 'test.body': 'Voici à quoi ressembleront les alertes de Buddy Optimizer.',
    'update.title': 'Mise à jour prête', 'update.body': 'Buddy Optimizer {v} a été téléchargé. Redémarrez l’app pour l’installer.'
  },
  de: {
    'tray.open': 'Buddy Optimizer öffnen', 'tray.lock': 'Sperren', 'tray.quit': 'Beenden',
    'alert.gpuTemp.title': 'GPU wird heiß', 'alert.gpuTemp.body': 'GPU-Temperatur {v}° (Grenze {limit}°). Prüfe Luftstrom und Lüfterkurve.',
    'alert.cpuLoad.title': 'Hohe CPU-Last', 'alert.cpuLoad.body': 'Die CPU liegt seit einer Weile bei {v} % (Grenze {limit} %).',
    'alert.ramLoad.title': 'Arbeitsspeicher fast voll', 'alert.ramLoad.body': 'RAM bei {v} % (Grenze {limit} %). Schließe Hintergrund-Apps.',
    'alert.ping.title': 'Hohe Latenz', 'alert.ping.body': 'Durchschnittlicher Ping {v} ms (Grenze {limit} ms).',
    'done.title': 'Optimierung abgeschlossen', 'done.body': '{ok} Änderungen übernommen, {fail} fehlgeschlagen.', 'done.reboot': 'Starte den PC neu, um alles zu übernehmen.',
    'test.title': 'Benachrichtigungen aktiv', 'test.body': 'So sehen Hinweise von Buddy Optimizer aus.',
    'update.title': 'Update bereit', 'update.body': 'Buddy Optimizer {v} wurde heruntergeladen. Starte die App neu, um es zu installieren.'
  }
}

export function t(lang: Language, key: string): string {
  return strings[lang]?.[key] ?? strings.en[key] ?? key
}
