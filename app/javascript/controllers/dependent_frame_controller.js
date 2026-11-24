import { Controller } from "@hotwired/stimulus"

// Reloads a Turbo Frame when a <select> changes (e.g. locations of the chosen
// customer). The URL template contains ":id", replaced by the selected value.
export default class extends Controller {
  static targets = ["frame"]
  static values = { url: String }

  change(event) {
    const value = event.target.value
    if (!value) {
      this.frameTarget.innerHTML = ""
      return
    }
    this.frameTarget.src = this.urlValue.replace(":id", encodeURIComponent(value))
  }
}
