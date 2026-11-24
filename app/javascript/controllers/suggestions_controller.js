import { Controller } from "@hotwired/stimulus"

// Reloads the suggestions frame whenever date, time or duration change.
export default class extends Controller {
  static targets = ["date", "time", "duration", "frame"]
  static values = { url: String }

  refresh() {
    if (!this.hasFrameTarget) return
    const params = new URLSearchParams({
      date: this.dateTarget.value,
      start_time: this.timeTarget.value,
      duration_minutes: this.durationTarget.value
    })
    this.frameTarget.src = `${this.urlValue}?${params}`
  }
}
