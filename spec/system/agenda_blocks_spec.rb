# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Blocos da agenda do dia", :js do
  let(:scenario) { build_work_order_scenario }
  let(:diego) { create_technician(scenario[:organization], name: "Diego Alves") }

  # Which time variant a block shows, how many lines the order number takes
  # and whether the number or the time runs past the block's edge.
  def block_layout(order)
    page.evaluate_script(<<~JS, "a[href='#{work_order_path(order)}']")
      (() => {
        const block = document.querySelector("section[aria-label='Linha do tempo do dia'] " + arguments[0])
        const lines = block.querySelectorAll(":scope > span")
        const number = lines[1].querySelector(":scope > span")
        const inline = lines[1].querySelectorAll(":scope > span")[1]
        const shown = (node) => getComputedStyle(node).display !== "none"
        const rects = (node) => {
          const range = document.createRange()
          range.selectNodeContents(node)
          return [...range.getClientRects()]
        }
        const limit = block.getBoundingClientRect().right - parseFloat(getComputedStyle(block).paddingRight)
        const cut = [number, inline, lines[2]].filter(shown)
          .some((node) => Math.max(...rects(node).map((rect) => rect.right)) > limit + 0.5)
        const numberLines = new Set(rects(number).map((rect) => Math.round(rect.top))).size
        return { inline: shown(inline), ownLine: shown(lines[2]), numberLines, cut }
      })()
    JS
  end

  it "mostra número e horário inteiros: lado a lado, em linhas próprias ou só o número" do
    short_order = open_work_order(scenario, title: "Curta")
    middle_order = open_work_order(scenario, title: "Média")
    long_order = open_work_order(scenario, title: "Longa")
    schedule(scenario, short_order, [diego], from: tuesday_at(8), to: tuesday_at(9))
    schedule(scenario, middle_order, [diego], from: tuesday_at(10), to: tuesday_at(11, 30))
    schedule(scenario, long_order, [diego], from: tuesday_at(13), to: tuesday_at(16))

    travel_to(tuesday_at(7)) do
      sign_in_as(scenario[:coordinator])
      visit agenda_index_path(data: "2026-12-01")

      expect(page).to have_css("section[aria-label='Linha do tempo do dia']")
      expect(block_layout(long_order)).to eq("inline" => true, "ownLine" => false, "numberLines" => 1, "cut" => false)
      expect(block_layout(middle_order)).to eq("inline" => false, "ownLine" => true, "numberLines" => 1, "cut" => false)
      expect(block_layout(short_order)).to include("inline" => false, "ownLine" => false, "cut" => false)
    end
  end
end
