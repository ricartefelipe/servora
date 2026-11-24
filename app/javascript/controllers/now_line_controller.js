import { Controller } from "@hotwired/stimulus"

// Live "now" marker on a day timeline (agenda, dashboard).
//
// The server renders the initial position, so the marker is correct without
// JavaScript; this controller only keeps it current. The timeline window is
// given as epoch milliseconds (start and end of the visible day's range in the
// organization's zone), which makes the position independent of the browser's
// time zone. The clock label is formatted in the organization's zone.
//
// The device clock may be off, so the difference to the server clock is
// measured once and stored in a data attribute: a page restored from the
// Turbo cache keeps the original measurement instead of comparing the current
// time with a stale server timestamp.
//
// Targets:
//   marker - elements hidden while now is outside the window (or not today)
//   line   - SVG <line> in a viewBox of `viewBoxWidth` units; x1/x2 are set
//   pill   - nested SVG viewport whose x is set as a percentage of the width
//   pillBody - group shifted to keep the pill inside the timeline near its end
//   time   - text showing HH:MM in the pill
//   label  - screen-reader text "Agora, HH:MM" (aria-live="off" in markup)
//
// Nothing here animates, so reduced-motion preferences are respected as is.
const PILL_END_THRESHOLD = 0.98
const PILL_END_SHIFT = -22

export default class NowLineController extends Controller {
  static targets = ["marker", "line", "pill", "pillBody", "time", "label"]
  static values = {
    start: Number,
    end: Number,
    serverNow: Number,
    skew: Number,
    timeZone: String,
    utcOffset: Number,
    viewBoxWidth: { type: Number, default: 960 },
    interval: { type: Number, default: 30000 }
  }

  connect() {
    if (!this.hasSkewValue) this.skewValue = this.hasServerNowValue ? this.serverNowValue - Date.now() : 0
    this.formatter = this.buildFormatter()
    this.update()
    this.revealNow()
    this.timer = setInterval(this.update, this.intervalValue)
    document.addEventListener("visibilitychange", this.refresh)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.refresh)
  }

  // Timers are throttled in background tabs: catch up as soon as the tab is shown.
  refresh = () => {
    if (document.visibilityState === "visible") this.update()
  }

  update = () => {
    const now = Date.now() + this.skewValue
    const fraction = (now - this.startValue) / (this.endValue - this.startValue)
    const visible = Number.isFinite(fraction) && fraction >= 0 && fraction < 1

    this.markerTargets.forEach((element) => element.toggleAttribute("hidden", !visible))
    if (!visible) return

    const x = (fraction * this.viewBoxWidthValue).toFixed(2)
    this.lineTargets.forEach((line) => {
      line.setAttribute("x1", x)
      line.setAttribute("x2", x)
    })

    if (this.hasPillTarget) this.pillTarget.setAttribute("x", `${(fraction * 100).toFixed(3)}%`)
    if (this.hasPillBodyTarget) {
      const shift = fraction > PILL_END_THRESHOLD ? PILL_END_SHIFT : 0
      this.pillBodyTarget.setAttribute("transform", `translate(${shift} 0)`)
    }

    const time = this.format(now)
    this.setText(this.timeTargets, time)
    this.setText(this.labelTargets, `Agora, ${time}`)
  }

  // On narrow screens the timeline scrolls sideways: bring "now" into view once,
  // only when the container overflows and the marker is shown.
  revealNow() {
    const container = this.element
    const line = this.lineTargets[0]
    if (!line || container.scrollWidth <= container.clientWidth) return
    if (this.markerTargets.some((element) => element.hidden)) return

    const offset = line.getBoundingClientRect().left - container.getBoundingClientRect().left
    container.scrollLeft = Math.max(0, container.scrollLeft + offset - container.clientWidth / 2)
  }

  setText(elements, text) {
    elements.forEach((element) => {
      if (element.textContent !== text) element.textContent = text
    })
  }

  format(epoch) {
    if (this.formatter) return this.formatter.format(new Date(epoch))

    // Fallback without Intl time zone support: fixed offset sent by the server.
    const shifted = new Date(epoch + this.utcOffsetValue * 1000)
    const pad = (number) => String(number).padStart(2, "0")
    return `${pad(shifted.getUTCHours())}:${pad(shifted.getUTCMinutes())}`
  }

  // Never falls back to the browser's zone: without a zone name, the fixed offset is used.
  buildFormatter() {
    if (!this.timeZoneValue) return null
    try {
      return new Intl.DateTimeFormat("pt-BR", {
        hour: "2-digit",
        minute: "2-digit",
        hourCycle: "h23",
        timeZone: this.timeZoneValue
      })
    } catch {
      return null
    }
  }
}
