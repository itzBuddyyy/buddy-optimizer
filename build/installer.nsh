; Buddy Optimizer - custom NSIS steps
; Make sure the monitor helper is not running during install / uninstall,
; otherwise its files would be locked.

!macro customInit
  nsExec::Exec 'taskkill /F /IM BuddyMonitor.exe'
!macroend

!macro customUnInit
  nsExec::Exec 'taskkill /F /IM BuddyMonitor.exe'
!macroend
