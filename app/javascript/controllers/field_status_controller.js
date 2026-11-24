import { Controller } from "@hotwired/stimulus"
import { RETRY_EVENT, STATUS_EVENT, currentStatus, flush, park } from "controllers/field_queue"

// Sync chip of the field top bar (polite live region).
//
// It renders the state announced by field-sync ("field-sync:status") and,
// on screens without field-sync (the agenda), reads the shared queue itself
// and sends it when the device is online, so the chip never shows a state the
// queue does not have. "Tentar" asks for a new attempt through
// "field-sync:retry". Nothing is shown until the real state is known.
export default class FieldStatusController extends Controller {
  static targets = ["region", "variant", "offlineText", "pendingText", "retry"]
  static values = { url: String, contextKey: String }

  connect() {
    this.onStatus = (event) => this.render(event.detail)
    this.onOffline = () => this.refresh()
    // send() reports its own failures through the status event; nothing to await here.
    this.onOnline = () => (this.standalone ? void this.send() : this.refresh())
    this.onRetry = () => { if (this.standalone) void this.send() }
    window.addEventListener(STATUS_EVENT, this.onStatus)
    window.addEventListener("offline", this.onOffline)
    window.addEventListener("online", this.onOnline)
    window.addEventListener(RETRY_EVENT, this.onRetry)
    this.refresh()
    if (this.standalone && navigator.onLine) void this.send()
  }

  disconnect() {
    window.removeEventListener(STATUS_EVENT, this.onStatus)
    window.removeEventListener("offline", this.onOffline)
    window.removeEventListener("online", this.onOnline)
    window.removeEventListener(RETRY_EVENT, this.onRetry)
  }

  // True when no field-sync controller sends the queue on this screen.
  get standalone() {
    return !document.querySelector("[data-controller~='field-sync']")
  }

  retry() {
    window.dispatchEvent(new CustomEvent(RETRY_EVENT))
  }

  refresh() {
    this.render(currentStatus(this.contextKeyValue))
  }

  // A refused or conflicting operation is kept for the screen of its work
  // order; an accepted visit change reloads the agenda so it shows the new state.
  async send() {
    let changedVisits = false
    await flush({
      url: this.urlValue,
      contextKey: this.contextKeyValue,
      onOutcome: (operation, outcome) => {
        if (outcome.status !== "applied") park(this.contextKeyValue, operation, outcome)
        else if (operation.kind.startsWith("visit_")) changedVisits = true
      }
    })
    if (changedVisits && this.element.isConnected && window.Turbo) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    }
  }

  render({ state, pending }) {
    const count = pending === 1 ? "1 pendente" : `${pending} pendentes`
    this.offlineTextTarget.textContent = pending > 0 ? `Offline · ${count}` : "Offline"
    this.pendingTextTarget.textContent = `Sincronizando · ${count}`
    this.variantTargets.forEach((variant) => { variant.hidden = variant.dataset.state !== state })
    // Keep keyboard focus in the bar when "Tentar" disappears during a retry,
    // and give it back to the button if the retry fails again.
    if (state !== "error" && document.activeElement === this.retryTarget) {
      this.regionTarget.focus()
      this.restoreRetryFocus = true
    }
    this.retryTarget.hidden = state !== "error"
    if (state === "error" && this.restoreRetryFocus) this.retryTarget.focus()
    if (state !== "pending") this.restoreRetryFocus = false
    this.element.dataset.state = state
  }
}
