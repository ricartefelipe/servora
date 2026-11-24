import { Controller } from "@hotwired/stimulus"

// Device data hygiene. Field drafts are stored under a key derived from the
// user + organization context. Whenever the page context differs from the last
// one seen (logout, organization switch, another user), every stored draft is
// removed before anything else runs.
const MARKER = "servora:context"
const PREFIX = "servora:"

export default class extends Controller {
  static values = { key: String }

  connect() {
    const previous = localStorage.getItem(MARKER)
    if (previous !== this.keyValue) {
      this.purge()
      localStorage.setItem(MARKER, this.keyValue)
    }
  }

  purge() {
    Object.keys(localStorage)
      .filter((key) => key.startsWith(PREFIX) && key !== MARKER)
      .forEach((key) => localStorage.removeItem(key))
    if (window.indexedDB?.deleteDatabase) window.indexedDB.deleteDatabase("servora-drafts")
  }
}
