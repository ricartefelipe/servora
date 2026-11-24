import { Controller } from "@hotwired/stimulus"

// Accessible tabs (WAI-ARIA Authoring Practices): arrow keys move between
// tabs, Home/End jump, the selected tab is reflected in the URL hash.
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    const fromHash = this.tabTargets.find((tab) => tab.dataset.key === window.location.hash.slice(1))
    this.select(fromHash || this.tabTargets[0], false)
  }

  activate(event) {
    event.preventDefault()
    this.select(event.currentTarget, true)
  }

  keydown(event) {
    const index = this.tabTargets.indexOf(event.currentTarget)
    const last = this.tabTargets.length - 1
    const moves = { ArrowRight: index + 1, ArrowLeft: index - 1, Home: 0, End: last }
    if (!(event.key in moves)) return
    event.preventDefault()
    const next = this.tabTargets[(moves[event.key] + last + 1) % (last + 1)]
    this.select(next, true)
    next.focus()
  }

  select(tab, updateHash) {
    if (!tab) return
    this.tabTargets.forEach((candidate) => {
      const selected = candidate === tab
      candidate.setAttribute("aria-selected", selected)
      candidate.tabIndex = selected ? 0 : -1
    })
    this.panelTargets.forEach((panel) => { panel.hidden = panel.id !== tab.getAttribute("aria-controls") })
    if (updateHash) history.replaceState(null, "", `#${tab.dataset.key}`)
  }
}
