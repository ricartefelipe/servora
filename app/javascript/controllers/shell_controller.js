import { Controller } from "@hotwired/stimulus"

// Off-canvas navigation for small screens. While closed the panel is also
// "invisible", so its links are unreachable by keyboard and screen readers.
// Keeps aria-expanded in sync and returns focus to the toggle on close.
export default class extends Controller {
  static targets = ["sidebar", "overlay", "toggle"]

  open() {
    this.sidebarTarget.classList.remove("-translate-x-full", "invisible")
    this.overlayTarget.hidden = false
    this.toggleTarget?.setAttribute("aria-expanded", "true")
    this.sidebarTarget.querySelector("a, button")?.focus()
  }

  close() {
    if (this.overlayTarget.hidden) return
    this.sidebarTarget.classList.add("-translate-x-full", "invisible")
    this.overlayTarget.hidden = true
    this.toggleTarget?.setAttribute("aria-expanded", "false")
    this.toggleTarget?.focus()
  }
}
