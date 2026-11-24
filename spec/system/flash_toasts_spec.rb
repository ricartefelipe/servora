# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Avisos (toasts)", :js do
  let(:scenario) { build_work_order_scenario }
  let(:notice_text) { "Cliente cadastrado." }
  let(:alert_text) { "Não foi possível concluir a operação." }

  # Delivers the toasts the same way the app does for Turbo Stream responses:
  # turbo_stream.update("flash", partial: "shared/flash", ...).
  def stream_flash(messages)
    html = ApplicationController.render(partial: "shared/flash", locals: { flash_messages: messages })
    stream = %(<turbo-stream action="update" target="flash"><template>#{html}</template></turbo-stream>)
    page.execute_script("Turbo.renderStreamMessage(arguments[0])", stream)
  end

  # Keeps the pointer away from the bottom-right corner so hover never pauses a timer.
  def park_pointer = page.driver.browser.mouse.move(x: 1, y: 1)

  def notice_toast = find("#flash [role='status']", text: notice_text)
  def alert_toast = find("#flash [role='alert']", text: alert_text)

  before do
    sign_in_as(scenario[:coordinator])
    find("h1")
    park_pointer
  end

  it "mantém o alerta depois que o aviso some e fecha o alerta pelo botão" do
    stream_flash("notice" => notice_text, "alert" => alert_text)

    expect(notice_toast["aria-live"]).to eq("polite")
    expect(alert_toast["aria-live"]).to be_nil
    expect(page).to have_css("#flash [role='alert']", count: 1)

    expect(page).to have_no_css("#flash [role='status']", text: notice_text, wait: 8)
    # Well past any timer a notice could have; errors only leave when dismissed.
    sleep 5
    expect(page).to have_css("#flash [role='alert']", text: alert_text)

    within(alert_toast) { click_on "Fechar aviso" }

    expect(page).to have_no_css("#flash [role='alert']")
  end

  it "pausa o aviso enquanto está em foco e fecha com Esc" do
    stream_flash("notice" => notice_text)

    close = within(notice_toast) { find_button("Fechar aviso") }
    page.execute_script("arguments[0].focus()", close)
    sleep 5.5

    expect(page).to have_css("#flash [role='status']", text: notice_text)

    close.send_keys(:escape)

    expect(page).to have_no_css("#flash [role='status']")
    expect(page.evaluate_script("document.activeElement.id")).to eq("conteudo")
  end
end
