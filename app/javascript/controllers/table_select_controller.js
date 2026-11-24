import { Controller } from "@hotwired/stimulus"

// Row selection for bulk actions on a list table.
//
// The row checkboxes are ordinary form controls joined to the bulk form
// through their form attribute, so the submission itself never depends on
// this controller. It keeps the page in sync with the selection: the header
// checkbox ("all on this page", indeterminate when partial), aria-selected
// on the rows, the bulk bar and its live count, the targets that make sense
// for the selected orders and the reason requirement of the chosen target.
export default class extends Controller {
  static targets = ["all", "row", "bar", "count", "announcer", "target", "reason", "reasonHint"]
  static values = { reasonRequired: Array }

  connect() {
    this.lastCount = this.selected.length
    this.refresh()
  }

  toggle() {
    this.refresh()
  }

  toggleAll() {
    const checked = this.allTarget.checked
    this.rowTargets.forEach((row) => { row.checked = checked })
    this.refresh()
  }

  clear(event) {
    if (this.selected.length === 0) return
    event?.preventDefault()
    this.rowTargets.forEach((row) => { row.checked = false })
    this.refresh()
    // The bar disappears; keep the focus on the list instead of losing it.
    if (this.hasAllTarget) this.allTarget.focus()
  }

  refresh() {
    const selected = this.selected
    const count = selected.length
    this.rowTargets.forEach((row) => {
      row.closest("tr")?.setAttribute("aria-selected", row.checked ? "true" : "false")
    })
    if (this.hasAllTarget) {
      this.allTarget.checked = count > 0 && count === this.rowTargets.length
      this.allTarget.indeterminate = count > 0 && count < this.rowTargets.length
      this.allTarget.disabled = this.rowTargets.length === 0
    }
    if (this.hasBarTarget) this.barTarget.hidden = count === 0
    const text = this.countText(count)
    if (this.hasCountTarget) this.countTarget.textContent = text
    if (this.hasAnnouncerTarget && count !== this.lastCount) {
      this.announcerTarget.textContent = count === 0 ? "Seleção limpa" : text
    }
    this.lastCount = count
    this.syncTargets(selected)
    this.syncReason()
  }

  // Options that no selected order can move to are disabled (the server
  // still decides per order and reports the ones it could not change).
  syncTargets(selected) {
    if (!this.hasTargetTarget) return
    const allowed = new Set(selected.flatMap((row) => (row.dataset.targets || "").split(" ").filter(Boolean)))
    Array.from(this.targetTarget.options).forEach((option) => {
      if (option.value) option.disabled = selected.length > 0 && !allowed.has(option.value)
    })
    if (this.targetTarget.selectedOptions[0]?.disabled) this.targetTarget.value = ""
  }

  syncReason() {
    if (!this.hasTargetTarget || !this.hasReasonTarget) return
    const option = this.targetTarget.selectedOptions[0]
    const required = this.reasonRequiredValue.includes(this.targetTarget.value)
    this.reasonTarget.required = required
    if (this.hasReasonHintTarget) {
      this.reasonHintTarget.textContent = required
        ? `Obrigatório para ${option.textContent.trim()}.`
        : "Opcional para esta situação."
    }
  }

  countText(count) {
    return count === 1 ? "1 selecionada" : `${count} selecionadas`
  }

  get selected() {
    return this.rowTargets.filter((row) => row.checked)
  }
}
