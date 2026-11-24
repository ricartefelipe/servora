import { Controller } from "@hotwired/stimulus"

// Accessible tabs (WAI-ARIA Authoring Practices): arrow keys move between
// tabs, Home/End jump, the selected tab is reflected in the URL hash.
//
// Redirects followed by Turbo drop the URL fragment, so the last tab chosen
// on a page is also kept in sessionStorage (only the tab key, per path) and
// restored when the page comes back after a form submission.
const STORAGE_PREFIX = "servora:tab:"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    const key = window.location.hash.slice(1) || this.remembered()
    const tab = this.tabTargets.find((candidate) => candidate.dataset.key === key)
    this.select(tab || this.tabTargets[0], false)
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
    if (!updateHash) return
    history.replaceState(null, "", `#${tab.dataset.key}`)
    this.remember(tab.dataset.key)
  }

  get storageKey() {
    return `${STORAGE_PREFIX}${window.location.pathname}`
  }

  remembered() {
    try { return sessionStorage.getItem(this.storageKey) } catch { return null }
  }

  remember(key) {
    try { sessionStorage.setItem(this.storageKey, key) } catch { /* storage unavailable: hash still works */ }
  }
}
