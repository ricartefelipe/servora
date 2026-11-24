import { Controller } from "@hotwired/stimulus"

// Registers the service worker used by the field area (static assets and an
// offline notice only; pages and data are never cached).
export default class extends Controller {
  connect() {
    if ("serviceWorker" in navigator) navigator.serviceWorker.register("/service-worker", { scope: "/" }).catch(() => {})
  }
}
