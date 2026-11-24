import { Controller } from "@hotwired/stimulus"

const MIN_LENGTH = 2
const DEBOUNCE_MS = 150

// Command palette: a native <dialog> opened with Ctrl+K / Cmd+K or from the
// sidebar and top bar buttons. The input is a combobox: results are loaded
// into a Turbo Frame (debounced, from the tenant-scoped search endpoint) and
// focus never leaves the input; the active option is exposed through
// aria-activedescendant and aria-selected. Escape is handled by the dialog
// itself and focus returns to the element that opened the palette.
export default class CommandPaletteController extends Controller {
  static targets = ["dialog", "input", "frame", "option", "status", "hint", "shortcut"]
  static values = { url: String }

  connect() {
    this.index = -1
    this.stale = false
    this.openOnLoad = false
    this.timer = null
    // A page restored from the Turbo cache may carry an old term or results.
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
      this.reset()
    }
    const platform = navigator.userAgentData?.platform || navigator.platform || ""
    if (/mac|iphone|ipad/i.test(platform)) {
      this.shortcutTargets.forEach((element) => { element.textContent = "⌘ K" })
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  open(event) {
    if (!this.hasDialogTarget) return
    event?.preventDefault()
    if (!this.dialogTarget.open) {
      this.opener = event?.type === "click" ? event.currentTarget : document.activeElement
      this.dialogTarget.showModal()
    }
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  close() {
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  closed() {
    clearTimeout(this.timer)
    this.timer = null
    this.openOnLoad = false
    // A search interrupted by closing would leave stale results on reopening.
    if (this.stale) this.search()
    const opener = this.opener
    this.opener = null
    if (opener && opener !== document.body && opener.isConnected) opener.focus()
  }

  // A press and release both on the dialog element itself (not its content)
  // is a click on the backdrop; a text selection dragged out of the input is not.
  pressed(event) {
    this.pressedOnBackdrop = event.target === this.dialogTarget
  }

  backdrop(event) {
    if (this.pressedOnBackdrop && event.target === this.dialogTarget) this.close()
    this.pressedOnBackdrop = false
  }

  // Escape anywhere inside the dialog belongs to the dialog, not to page handlers.
  escape(event) {
    if (event.key === "Escape") event.stopPropagation()
  }

  search() {
    clearTimeout(this.timer)
    this.timer = null
    const term = this.term
    if (term.length < MIN_LENGTH) {
      this.reset()
      return
    }
    this.stale = true
    this.timer = setTimeout(() => this.load(term), DEBOUNCE_MS)
  }

  navigate(event) {
    if (event.isComposing) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.move(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.move(-1)
        break
      case "Enter":
        event.preventDefault()
        this.submit()
        break
      case "Tab":
        // The input is the only focusable control: Tab cycles the options instead.
        event.preventDefault()
        this.move(event.shiftKey ? -1 : 1)
        break
      case "Escape":
        // The dialog closes itself; keep the key from reaching page-level handlers.
        event.stopPropagation()
        break
    }
  }

  hover(event) {
    const position = this.optionTargets.indexOf(event.currentTarget)
    if (position !== this.index) this.activate(position, { scroll: false })
  }

  // Plain clicks navigate through Turbo (the frame targets _top); close first
  // so the page is not cached with the palette open.
  choose(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    this.close()
  }

  loaded() {
    // A slow response may arrive after the term was cleared.
    if (this.term.length < MIN_LENGTH) {
      this.reset()
      return
    }
    this.stale = this.requestedTerm !== this.term || this.timer !== null
    this.activate(this.optionTargets.length > 0 ? 0 : -1)
    this.announce()
    if (this.openOnLoad && !this.stale) {
      this.openOnLoad = false
      this.optionTargets[0]?.click()
    }
  }

  failed(event) {
    event.preventDefault()
    this.stale = false
    this.openOnLoad = false
    const message = document.createElement("p")
    message.className = "px-4 py-6 text-[13px] text-white/70"
    message.dataset.searchMessage = ""
    message.textContent = "Não foi possível carregar os resultados. Recarregue a página e tente novamente."
    this.frameTarget.replaceChildren(message)
    this.activate(-1)
    this.announce()
  }

  // Closes the palette before Turbo caches the page.
  dismiss() {
    this.close()
  }

  // private

  get term() {
    return this.inputTarget.value.trim().replace(/\s+/g, " ")
  }

  load(term) {
    this.timer = null
    this.requestedTerm = term
    const url = new URL(this.urlValue, window.location.href)
    url.searchParams.set("q", term)
    this.frameTarget.src = url.href
  }

  // Enter opens the active option. While newer results are still on their
  // way, it waits for them and opens the first match.
  submit() {
    if (this.term.length < MIN_LENGTH) return
    if (this.stale) {
      this.openOnLoad = true
      if (this.timer) {
        clearTimeout(this.timer)
        this.load(this.term)
      }
      return
    }
    this.optionTargets[this.index]?.click()
  }

  move(step) {
    const count = this.optionTargets.length
    if (count === 0) return
    if (this.index < 0) {
      this.activate(step > 0 ? 0 : count - 1)
      return
    }
    this.activate((this.index + step + count) % count)
  }

  activate(position, { scroll = true } = {}) {
    this.index = position
    this.optionTargets.forEach((option, index) => option.setAttribute("aria-selected", String(index === position)))
    const active = this.optionTargets[position]
    if (active) {
      this.inputTarget.setAttribute("aria-activedescendant", active.id)
      if (scroll) active.scrollIntoView({ block: "nearest" })
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
    this.inputTarget.setAttribute("aria-expanded", String(this.optionTargets.length > 0))
  }

  announce() {
    const count = this.optionTargets.length
    const message = this.frameTarget.querySelector("[data-search-message]")
    if (count === 0) {
      this.statusTarget.textContent = message?.textContent.trim().replace(/\s+/g, " ") || ""
      return
    }
    const noun = count === 1 ? "resultado" : "resultados"
    this.statusTarget.textContent = `${count} ${noun}. Use as setas para navegar e Enter para abrir.`
  }

  reset() {
    this.stale = false
    this.openOnLoad = false
    this.requestedTerm = null
    this.frameTarget.removeAttribute("src")
    this.frameTarget.replaceChildren(this.hintTarget.content.cloneNode(true))
    this.activate(-1)
    this.statusTarget.textContent = ""
  }
}
