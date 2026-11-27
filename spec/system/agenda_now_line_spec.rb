# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Marcador de agora na agenda", :js do
  let(:scenario) { build_work_order_scenario }

  before { create_technician(scenario[:organization], name: "Diego Alves") }

  # The server clock is frozen by travel_to; the browser keeps its real clock.
  # Moving Date.now forward and simulating the tab becoming visible makes the
  # controller recompute immediately instead of waiting for its timer.
  def advance_browser_clock(minutes)
    page.execute_script(<<~JS, minutes * 60_000)
      window.realDateNow ||= Date.now.bind(Date)
      const offset = arguments[0]
      Date.now = () => window.realDateNow() + offset
      document.dispatchEvent(new Event("visibilitychange"))
    JS
  end

  def line_x = page.evaluate_script("document.querySelector('[data-now-line-target=line]').getAttribute('x1')").to_f
  def pill_x = page.evaluate_script("document.querySelector('[data-now-line-target=pill]').getAttribute('x')")

  # Where the line is drawn, as a fraction of the first row's timeline width.
  def rendered_fraction
    page.evaluate_script(<<~JS)
      (() => {
        const line = document.querySelector("[data-now-line-target=line]").getBoundingClientRect()
        const lane = document.querySelector("ul[role=list] > li > div.grid").getBoundingClientRect()
        return (line.left + line.width / 2 - lane.left) / lane.width
      })()
    JS
  end

  def hidden_markers
    page.evaluate_script("[...document.querySelectorAll('[data-now-line-target~=marker]')].map((node) => node.hidden)")
  end

  it "posiciona a linha pelo relógio e se oculta depois do horário da agenda" do
    travel_to(tuesday_at(10)) do
      sign_in_as(scenario[:coordinator])
      visit agenda_index_path

      # The controller stores the clock difference to the server when it connects.
      expect(page).to have_css("[data-controller='now-line'][data-now-line-skew-value]")
      # Diego works 08:00–18:00: 10:00 is a fifth of the timeline.
      expect(line_x).to be_within(1).of(192)
      expect(rendered_fraction).to be_within(0.005).of(0.2)
      expect(page).to have_css("[data-now-line-target='time']", text: "10:00")
      expect(page).to have_css(".sr-only[aria-live='off']", text: "Agora, 10:00", visible: :all)

      advance_browser_clock(150)
      expect(page).to have_css("[data-now-line-target='time']", text: "12:30")
      expect(page).to have_css(".sr-only", text: "Agora, 12:30", visible: :all)
      expect(line_x).to be_within(1).of(432)
      expect(pill_x).to match(/\A4[45]\.\d{3}%\z/)
      expect(pill_x.to_f).to be_within(0.1).of(45)
      expect(rendered_fraction).to be_within(0.005).of(0.45)
      expect(hidden_markers).to eq([false, false, false])

      advance_browser_clock((12 * 60) + 30)
      expect(hidden_markers).to eq([true, true, true])
    end
  end
end
