import { Controller } from "@hotwired/stimulus"

// Toast notification. Notices clear themselves after `timeout` milliseconds and
// pause while hovered or while focus is inside, so they can always be read.
// A timeout of 0 marks the toast as persistent: errors stay until dismissed.
// Esc closes the toast that holds focus.
export default class extends Controller {
  static values = { timeout: { type: Number, default: 5000 } }

  connect() {
    this.hovered = false
    this.focused = false
    this.element.addEventListener("mouseenter", this.pointerEnter)
    this.element.addEventListener("mouseleave", this.pointerLeave)
    this.element.addEventListener("focusin", this.focusIn)
    this.element.addEventListener("focusout", this.focusOut)
    this.element.addEventListener("keydown", this.keydown)
    this.start()
  }

  disconnect() {
    this.stop()
    this.element.removeEventListener("mouseenter", this.pointerEnter)
    this.element.removeEventListener("mouseleave", this.pointerLeave)
    this.element.removeEventListener("focusin", this.focusIn)
    this.element.removeEventListener("focusout", this.focusOut)
    this.element.removeEventListener("keydown", this.keydown)
  }

  get persistent() {
    return this.timeoutValue <= 0
  }

  start() {
    this.stop()
    if (this.persistent || this.dismissed || this.hovered || this.focused) return

    this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
  }

  stop() {
    clearTimeout(this.timer)
    this.timer = null
  }

  pointerEnter = () => {
    this.hovered = true
    this.stop()
  }

  pointerLeave = () => {
    this.hovered = false
    this.start()
  }

  focusIn = () => {
    this.focused = true
    this.stop()
  }

  focusOut = (event) => {
    if (this.element.contains(event.relatedTarget)) return

    this.focused = false
    this.start()
  }

  keydown = (event) => {
    if (event.key !== "Escape" || event.defaultPrevented) return

    event.preventDefault()
    event.stopPropagation()
    this.dismiss()
  }

  dismiss() {
    if (this.dismissed) return

    this.dismissed = true
    this.stop()
    const hadFocus = this.element.contains(document.activeElement)

    const finish = () => {
      const next = hadFocus ? this.nextFocusTarget() : null
      this.element.remove()
      next?.focus({ preventScroll: true })
    }

    if (this.prefersReducedMotion || typeof this.element.animate !== "function") {
      finish()
      return
    }

    const exit = this.element.animate(
      [{ opacity: 1, transform: "translateY(0)" }, { opacity: 0, transform: "translateY(4px)" }],
      { duration: 140, easing: "ease-in", fill: "forwards" }
    )
    exit.finished.then(finish, finish)
  }

  // Keeps keyboard users in place: the next toast's close button when there is
  // one, otherwise the main content landmark.
  nextFocusTarget() {
    const toasts = Array.from(document.querySelectorAll("[data-controller~='flash']"))
      .filter((toast) => toast !== this.element && toast.isConnected)
    const button = toasts[0]?.querySelector("button")
    if (button) return button

    const main = document.getElementById("conteudo")
    if (main && !main.hasAttribute("tabindex")) main.setAttribute("tabindex", "-1")
    return main
  }

  get prefersReducedMotion() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false
  }
}
