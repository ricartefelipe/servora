import { Controller } from "@hotwired/stimulus"

// Auto-dismissing toast. Pauses while hovered or focused so it can be read.
export default class extends Controller {
  static values = { timeout: { type: Number, default: 5000 } }

  connect() {
    this.start()
    this.element.addEventListener("mouseenter", this.stop)
    this.element.addEventListener("focusin", this.stop)
    this.element.addEventListener("mouseleave", this.start)
  }

  disconnect() {
    this.stop()
  }

  start = () => {
    this.stop()
    this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
  }

  stop = () => {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.remove()
  }
}
