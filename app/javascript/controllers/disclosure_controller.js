import { Controller } from "@hotwired/stimulus"

// Closes a <details> menu on outside click or Escape.
export default class extends Controller {
  connect() {
    this.outside = (event) => {
      if (!this.element.contains(event.target)) this.element.open = false
    }
    this.escape = (event) => {
      if (event.key === "Escape" && this.element.open) {
        this.element.open = false
        this.element.querySelector("summary")?.focus()
      }
    }
    document.addEventListener("click", this.outside)
    document.addEventListener("keydown", this.escape)
  }

  disconnect() {
    document.removeEventListener("click", this.outside)
    document.removeEventListener("keydown", this.escape)
  }
}
