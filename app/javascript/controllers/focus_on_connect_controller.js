import { Controller } from "@hotwired/stimulus"

// Moves focus to an element when it appears (e.g. form error summaries) so
// screen reader users are told about the problem.
export default class extends Controller {
  connect() {
    this.element.focus({ preventScroll: false })
  }
}
