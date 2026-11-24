# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Página inicial" do
  it "apresenta a proposta do produto" do
    visit root_path

    expect(page).to have_css("h1", text: "Da solicitação do cliente ao resultado de cada serviço.")
    expect(page).to have_link("Ir para o conteúdo", href: "#conteudo", visible: :all)
  end

  it "carrega o JavaScript da aplicação no navegador headless", :js do
    visit root_path

    expect(page).to have_css("h1")
    expect(page.evaluate_script("typeof Turbo")).to eq("object")
  end
end
