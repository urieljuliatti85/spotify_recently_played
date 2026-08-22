import { createRoot } from "react-dom/client"
import App from "../components/App"
import "../styles/application.css"

const mount = document.getElementById("app")

if (mount) {
  createRoot(mount).render(
    <App
      connectPath={mount.dataset.connectPath}
      flash={mount.dataset.flash || null}
      clientId={mount.dataset.clientId || null}
      listenRedirectUri={mount.dataset.listenRedirectUri}
    />
  )
}
