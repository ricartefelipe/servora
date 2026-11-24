# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Portal do cliente no celular", :js do
  let(:scenario) { build_work_order_scenario }
  let(:contact) { create(:customer_contact, customer: scenario[:customer], portal_enabled: true, name: "Paula Reis") }

  def portal_link
    organization = scenario[:organization]
    grant = in_tenant(organization) { Portal::IssueGrant.new(contact:, purpose: "portal").call }
    Portal::DeliverGrant.new(organization_id: organization.id, grant_id: grant.id).call
    URI.parse(ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{http://\S+/portal/acesso/[\w-]+}]).request_uri
  end

  it "abre um chamado e navega sem rolagem horizontal" do
    page.current_window.resize_to(390, 844)
    visit portal_link
    click_on "Continuar"

    click_on "Abrir chamado", match: :first
    fill_in "Resumo", with: "Split da recepção pingando"
    fill_in "Detalhes", with: "Água escorrendo pela parede desde ontem."
    choose "Urgente — equipamento parado"
    click_on "Enviar chamado"
    expect(page).to have_text("Nossa equipe vai analisar.")
    expect(page).to have_text("Em análise")

    [portal_root_path, portal_work_orders_path, portal_equipment_index_path, portal_visits_path,
     portal_receivables_path].each do |path|
      visit path
      overflow = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
      expect(overflow).to be <= 0, "#{path} transborda #{overflow}px"
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
