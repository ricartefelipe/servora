# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Busca rápida", :js do
  let(:scenario) { build_work_order_scenario }
  let(:input_label) { "Buscar ordens de serviço, clientes, equipamentos e orçamentos" }
  let!(:work_order) do
    in_tenant(scenario[:organization]) { scenario[:customer].update!(name: "Refrigeração Horizonte Ltda.") }
    open_work_order(scenario, title: "Compressor Horizonte sem partida")
  end

  def selected_option = find('[role="option"][aria-selected="true"]')
  def have_selected_option(text) = have_css('[role="option"][aria-selected="true"]', text:)

  it "abre com Ctrl+K, navega pelas setas e abre o resultado com Enter" do
    sign_in_as(scenario[:coordinator])
    expect(page).to have_css("h1")

    find("body").send_keys([:control, "k"])
    expect(page).to have_css("dialog#busca-rapida[open]")
    expect(page).to have_text("Digite ao menos 2 caracteres")

    fill_in input_label, with: "horizonte"
    within("dialog#busca-rapida") do
      expect(page).to have_css('[role="group"]', text: /ordens de serviço/i)
      expect(page).to have_css('[role="group"]', text: /clientes/i)
    end
    expect(page).to have_selected_option(work_order.number)
    input = find_field(input_label)
    expect(input["aria-activedescendant"]).to eq(selected_option[:id])
    expect(input["aria-expanded"]).to eq("true")

    input.send_keys(:down)
    expect(page).to have_selected_option("Refrigeração Horizonte Ltda.")
    expect(find_field(input_label)["aria-activedescendant"]).to eq(selected_option[:id])
    input.send_keys(:up)
    expect(page).to have_selected_option(work_order.number)
    input.send_keys(:down, :enter)

    expect(page).to have_current_path(customer_path(scenario[:customer]))
    expect(page).to have_no_css("dialog[open]")
  end

  it "fecha com Esc e devolve o foco ao botão que abriu a busca" do
    sign_in_as(scenario[:coordinator])

    find("header button[aria-label='Buscar']").click
    expect(page).to have_css("dialog#busca-rapida[open]")
    fill_in input_label, with: "x"
    expect(page).to have_no_css('[role="option"]')

    find_field(input_label).send_keys(:escape)

    expect(page).to have_no_css("dialog[open]")
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')")).to eq("Buscar")
  end

  it "informa quando nada é encontrado" do
    sign_in_as(scenario[:coordinator])

    within("#navegacao") { click_on "Buscar…" }
    fill_in input_label, with: "inexistente"

    expect(page).to have_text("Nenhum resultado para “inexistente”.")
    expect(page).to have_css("output", text: "Nenhum resultado", visible: :all)
  end
end
