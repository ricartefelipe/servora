import { Controller } from "@hotwired/stimulus"

// Opens the <dialog> as a modal when it is loaded into the "modal" frame and
// clears the frame when it closes, returning focus to the element that opened it.
export default class extends Controller {
  connect() {
    this.opener = document.activeElement
    this.element.showModal()
  }

  close() {
    this.element.close()
  }

  closed() {
    const frame = this.element.closest("turbo-frame")
    if (frame) {
      frame.removeAttribute("src")
      frame.innerHTML = ""
    }
    if (this.opener && document.contains(this.opener)) this.opener.focus()
  }
}
