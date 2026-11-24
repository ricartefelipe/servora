import { Controller } from "@hotwired/stimulus"

// Field operations with an offline queue.
//
// Submitting a form queues an operation (device-generated id, kind, the
// version the technician saw, payload) in localStorage and tries to send it.
// Without connection the operation stays queued and is sent when the browser
// comes back online; the server stores the outcome per operation id, so a
// resend never applies twice. Typed values are kept as drafts until synced.
//
// Keys use the "servora:" prefix plus the user/organization context key, so
// the local-context controller removes everything on logout or context switch.
const PREFIX = "servora:field:"

export default class extends Controller {
  static targets = ["status", "pending"]
  static values = { url: String, contextKey: String, workOrderId: String }

  connect() {
    this.onOnline = () => this.flush()
    window.addEventListener("online", this.onOnline)
    this.restoreDrafts()
    this.render()
    this.flush()
  }

  disconnect() {
    window.removeEventListener("online", this.onOnline)
  }

  get queueKey() {
    return `${PREFIX}${this.contextKeyValue}:queue`
  }

  draftKey(form) {
    return `${PREFIX}${this.contextKeyValue}:draft:${this.workOrderIdValue}:${form.dataset.draftId}`
  }

  queue() {
    try { return JSON.parse(localStorage.getItem(this.queueKey)) || [] } catch { return [] }
  }

  store(queue) {
    localStorage.setItem(this.queueKey, JSON.stringify(queue))
    this.render()
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
    const operation = {
      id: crypto.randomUUID(),
      kind: form.dataset.kind,
      version: form.dataset.version || null,
      work_order_id: this.workOrderIdValue,
      payload: this.payload(form),
      draft: this.draftKey(form)
    }
    if (!operation.payload) return
    this.store([...this.queue(), operation])
    this.flush()
  }

  payload(form) {
    const fields = {}
    Object.entries(this.values(form)).forEach(([name, value]) => {
      const key = name.replace(/^[a-z_]+\[(.+)\]$/, "$1")
      fields[key] = value
    })
    if (form.dataset.itemId) fields.item_id = form.dataset.itemId
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
    if (this.flushing) return
    this.flushing = true
    try {
      for (const operation of this.queue()) {
        const outcome = await this.send(operation)
        if (outcome === null) {
          this.show("Sem conexão. As informações estão salvas neste aparelho e serão enviadas quando a conexão voltar.")
          break
        }
        this.store(this.queue().filter((queued) => queued.id !== operation.id))
        localStorage.removeItem(operation.draft)
        this.report(operation, outcome)
      }
    } finally {
      this.flushing = false
      this.render()
    }
  }

  async send(operation) {
    const { draft, ...body } = operation
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({ operation: body })
      })
      if (response.status === 429 || response.status >= 500) return null
      if (response.status === 403 || response.status === 404) {
        return { status: "rejected", result: { error: "Você não tem mais acesso a esta ordem ou ela foi encerrada." } }
      }
      return await response.json()
    } catch {
      return null
    }
  }

  report(operation, outcome) {
    const form = [...this.element.querySelectorAll("form[data-draft-id]")]
      .find((candidate) => this.draftKey(candidate) === operation.draft)
    if (outcome.status === "applied") {
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

  show(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  render() {
    if (!this.hasPendingTarget) return
    const count = this.queue().filter((operation) => operation.work_order_id === this.workOrderIdValue).length
    this.pendingTarget.hidden = count === 0
    this.pendingTarget.textContent = count === 1 ? "1 registro aguardando envio." : `${count} registros aguardando envio.`
  }
}
