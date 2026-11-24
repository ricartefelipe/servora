import { Controller } from "@hotwired/stimulus"

// Table row density ("Confortável" or "Compacta"), chosen in a list toolbar
// and remembered on this device. The controller sits on <body> and writes
// data-density there; application.css shortens .sv-table rows under
// body[data-density="compact"]. Toolbars render radio inputs registered as
// "option" targets, kept in sync with the stored choice.
const STORAGE_KEY = "servora:density"
const DENSITIES = ["comfortable", "compact"]

export default class extends Controller {
  static targets = ["option"]

  connect() {
    this.apply(this.stored)
  }

  optionTargetConnected(option) {
    option.checked = option.value === this.current
  }

  choose(event) {
    const density = event.target.value
    if (!DENSITIES.includes(density)) return
    try {
      localStorage.setItem(STORAGE_KEY, density)
    } catch {
      // Storage may be unavailable (private mode); the choice lasts for this page.
    }
    this.apply(density)
  }

  apply(density) {
    this.element.dataset.density = density
    this.optionTargets.forEach((option) => { option.checked = option.value === density })
  }

  get current() {
    return this.element.dataset.density || this.stored
  }

  get stored() {
    try {
      const value = localStorage.getItem(STORAGE_KEY)
      return DENSITIES.includes(value) ? value : "comfortable"
    } catch {
      return "comfortable"
    }
  }
}
