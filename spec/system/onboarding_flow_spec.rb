# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cadastro, confirmação e primeira organização", :js do
  def path_from_last_mail(pattern)
    body = ActionMailer::Base.deliveries.last.html_part.body.to_s
    URI.parse(CGI.unescapeHTML(body[pattern])).request_uri
  end

  it "leva uma nova pessoa do cadastro ao convite da equipe" do
    visit new_user_registration_path
    fill_in "Nome completo", with: "Marina Duarte"
    fill_in "E-mail", with: "marina@servora.test"
    fill_in "Senha", with: "frase-secreta-longa", match: :prefer_exact
    fill_in "Confirme a senha", with: "frase-secreta-longa"
    click_on "Criar conta"
    expect(page).to have_text("Enviamos um link de confirmação")

    visit path_from_last_mail(%r{http://[^"]+/conta/confirmacao\?confirmation_token=[^"]+})
    click_on "Confirmar e-mail"
    expect(page).to have_text("Seu e-mail foi confirmado")

    fill_in "E-mail", with: "marina@servora.test"
    fill_in "Senha", with: "frase-secreta-longa"
    click_on "Entrar"
    expect(page).to have_text("Cadastre sua empresa")

    fill_in "Nome da empresa", with: "Ar Puro Climatização"
    select "Climatização e refrigeração", from: "Segmento"
    click_on "Criar organização"
    expect(page).to have_text("Organização criada")
    expect(page).to have_css("h2", text: "Primeiros passos")

    find("aside#navegacao").click_link("Equipe")
    fill_in "E-mail", with: "tecnico@servora.test"
    select "Técnico", from: "Perfil"
    click_on "Enviar convite"

    expect(page).to have_css("[role=status]", text: "Convite enviado para tecnico@servora.test")
    expect(page).to have_text("tecnico@servora.test")

    # The recurring outbox dispatcher (bin/jobs) delivers the e-mail.
    run_dispatcher
    expect(ActionMailer::Base.deliveries.last.to).to eq(["tecnico@servora.test"])
  end
end
