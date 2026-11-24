import { Controller } from "@hotwired/stimulus"
import { PREFIX, RETRY_EVENT, announce, enqueue, flush, readQueue, takeParked } from "controllers/field_queue"

// Field operations with an offline queue (see controllers/field_queue).
//
// Submitting a form queues an operation and tries to send it. Without
// connection the operation stays queued and is sent when the browser comes
// back online or when the sync chip asks for a retry. Typed values are kept as
// drafts until synced.
//
// Visit forms (data-kind="visit_*", data-visit-id) change the visit state:
// while queued their buttons are disabled and the matching
// [data-field-sync-queued-for] hint is shown; once the server answers, the
// screen is reloaded so the state-driven actions follow the server.
const NOTICE = "notice"
const VISIT_KIND = /^visit_/
const VISIT_APPLIED = {
  visit_travel: "Deslocamento iniciado.",
  visit_no_show: "Visita registrada como não atendida: cliente ausente."
}

export default class extends Controller {
  static targets = ["status", "pending"]
  static values = { url: String, contextKey: String, workOrderId: String }

  connect() {
    this.onOnline = () => this.flush()
    this.onOffline = () => announce(this.contextKeyValue)
    this.onRetry = () => this.flush()
    window.addEventListener("online", this.onOnline)
    window.addEventListener("offline", this.onOffline)
    window.addEventListener(RETRY_EVENT, this.onRetry)
    this.restoreDrafts()
    this.showNotice()
    takeParked(this.contextKeyValue, this.workOrderIdValue).forEach(({ operation, outcome }) => this.report(operation, outcome))
    this.render()
    announce(this.contextKeyValue)
    this.flush()
  }

  disconnect() {
    window.removeEventListener("online", this.onOnline)
    window.removeEventListener("offline", this.onOffline)
    window.removeEventListener(RETRY_EVENT, this.onRetry)
  }

  get noticeKey() {
    return `${PREFIX}${this.contextKeyValue}:${NOTICE}:${this.workOrderIdValue}`
  }

  draftKey(form) {
    return `${PREFIX}${this.contextKeyValue}:draft:${this.workOrderIdValue}:${form.dataset.draftId}`
  }

  queue() {
    return readQueue(this.contextKeyValue)
  }

  remember(event) {
    const form = event.target.form
    if (form?.dataset.draftId) localStorage.setItem(this.draftKey(form), JSON.stringify(this.values(form)))
  }

  restoreDrafts() {
    let restored = false
    this.element.querySelectorAll("form[data-draft-id]").forEach((form) => {
      const raw = localStorage.getItem(this.draftKey(form))
      if (!raw) return
      Object.entries(JSON.parse(raw)).forEach(([name, value]) => {
        const input = form.elements.namedItem(name)
        if (input && !input.disabled) input.value = value
      })
      restored = true
    })
    if (restored) this.show("Rascunho recuperado deste aparelho. Revise e salve.")
  }

  submit(event) {
    event.preventDefault()
    const form = event.target
    const draft = this.draftKey(form)
    if (VISIT_KIND.test(form.dataset.kind) && this.queue().some((operation) => operation.draft === draft)) return
    const operation = {
      id: crypto.randomUUID(),
      kind: form.dataset.kind,
      version: form.dataset.version || null,
      work_order_id: this.workOrderIdValue,
      payload: this.payload(form),
      draft
    }
    if (!operation.payload) return
    enqueue(this.contextKeyValue, operation)
    this.render()
    this.flush()
  }

  payload(form) {
    const fields = {}
    Object.entries(this.values(form)).forEach(([name, value]) => {
      const key = name.replace(/^[a-z_]+\[(.+)\]$/, "$1")
      fields[key] = value
    })
    if (form.dataset.itemId) fields.item_id = form.dataset.itemId
    if (form.dataset.visitId) fields.visit_id = form.dataset.visitId
    if (form.dataset.kind === "visit_travel") fields.at = new Date().toISOString()
    if (form.dataset.kind === "time_entry") {
      if (!fields.started_at || !fields.ended_at) return null
      fields.started_at = new Date(fields.started_at).toISOString()
      fields.ended_at = new Date(fields.ended_at).toISOString()
    }
    return fields
  }

  values(form) {
    const data = {}
    for (const element of form.elements) {
      if (element.name && !["submit", "button", "hidden"].includes(element.type) && element.name !== "authenticity_token") {
        data[element.name] = element.value
      }
    }
    return data
  }

  async flush() {
    let reload = false
    const sent = await flush({
      url: this.urlValue,
      contextKey: this.contextKeyValue,
      onOutcome: (operation, outcome) => {
        this.render()
        if (VISIT_KIND.test(operation.kind) && operation.work_order_id === this.workOrderIdValue) {
          reload = true
          this.keepNotice(this.visitMessage(operation, outcome))
        } else {
          this.report(operation, outcome)
        }
      },
      onFailure: (kind) => {
        this.show(kind === "server"
          ? "O servidor não respondeu. As informações continuam salvas neste aparelho; tente novamente em instantes."
          : "Sem conexão. As informações estão salvas neste aparelho e serão enviadas quando a conexão voltar.")
      }
    })
    if (sent) this.render()
    if (reload && this.element.isConnected) this.reload()
  }

  report(operation, outcome) {
    const form = [...this.element.querySelectorAll("form[data-draft-id]")]
      .find((candidate) => this.draftKey(candidate) === operation.draft)
    if (VISIT_KIND.test(operation.kind)) {
      this.show(this.visitMessage(operation, outcome))
    } else if (outcome.status === "applied") {
      if (form && outcome.result?.version !== undefined) form.dataset.version = outcome.result.version
      if (form && operation.kind === "time_entry") form.reset()
      this.show("Sincronizado com sucesso.")
    } else if (outcome.status === "conflict") {
      if (form && outcome.result?.version !== undefined) form.dataset.version = outcome.result.version
      const current = outcome.result?.response ?? outcome.result?.diagnosis ?? ""
      this.show(`Conflito: outra pessoa alterou este registro. Valor atual no servidor: "${current}". Revise e salve novamente.`)
    } else {
      this.show(`Não foi possível registrar: ${outcome.result?.error || "operação recusada"}.`)
    }
  }

  visitMessage(operation, outcome) {
    if (outcome.status === "applied") return VISIT_APPLIED[operation.kind] || "Sincronizado com sucesso."
    if (outcome.status === "conflict") {
      const label = outcome.result?.status_label
      return `A visita foi alterada por outra pessoa${label ? ` e agora está ${label.toLowerCase()}` : ""}. Confira a situação atual.`
    }
    return `Não foi possível registrar: ${outcome.result?.error || "operação recusada"}`
  }

  // The message survives the reload that brings the new visit state.
  keepNotice(message) {
    sessionStorage.setItem(this.noticeKey, message)
  }

  showNotice() {
    const message = sessionStorage.getItem(this.noticeKey)
    if (!message) return
    sessionStorage.removeItem(this.noticeKey)
    this.show(message)
  }

  reload() {
    if (window.Turbo) window.Turbo.visit(window.location.href, { action: "replace" })
    else window.location.reload()
  }

  show(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  render() {
    const queue = this.queue()
    if (this.hasPendingTarget) {
      const count = queue.filter((operation) => operation.work_order_id === this.workOrderIdValue).length
      this.pendingTarget.hidden = count === 0
      this.pendingTarget.textContent = count === 1 ? "1 registro aguardando envio." : `${count} registros aguardando envio.`
    }
    this.element.querySelectorAll("form[data-draft-id]").forEach((form) => {
      if (!VISIT_KIND.test(form.dataset.kind)) return
      const queued = queue.some((operation) => operation.draft === this.draftKey(form))
      for (const element of form.elements) {
        if (element.type === "submit") element.disabled = queued
      }
      this.element.querySelectorAll(`[data-field-sync-queued-for="${form.dataset.draftId}"]`)
        .forEach((hint) => { hint.hidden = !queued })
    })
  }
}
