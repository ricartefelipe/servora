import { Controller } from "@hotwired/stimulus"

// Demo mode sign-in: fills the e-mail and password fields with the chosen
// demonstration account and moves focus to the submit button, so the visitor
// only has to confirm. The fields are found by id (values), the outcome is
// announced through a polite live region.
export default class extends Controller {
  static targets = ["status"]
  static values = { password: String, emailField: String, passwordField: String }

  fill({ params: { email, message } }) {
    const emailField = document.getElementById(this.emailFieldValue)
    const passwordField = document.getElementById(this.passwordFieldValue)
    if (!emailField || !passwordField) return

    this.assign(emailField, email)
    this.assign(passwordField, this.passwordValue)
    if (this.hasStatusTarget) this.statusTarget.textContent = message

    const submit = emailField.form?.querySelector("[type=submit]")
    ;(submit || passwordField).focus()
  }

  assign(field, value) {
    field.value = value
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
