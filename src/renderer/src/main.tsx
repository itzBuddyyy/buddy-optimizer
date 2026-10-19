import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
// Inter variable with optical sizing: display cuts at large sizes, text cuts
// at small sizes - the closest freely licensed match to SF Pro's behaviour.
import '@fontsource-variable/inter/opsz.css'
import './styles/global.css'
import './styles/components.css'
import './styles/views.css'
import { SettingsProvider } from './lib/store'
import App from './App'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <SettingsProvider>
      <App />
    </SettingsProvider>
  </StrictMode>
)
