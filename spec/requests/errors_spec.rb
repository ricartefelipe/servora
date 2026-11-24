# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Error pages" do
  it "renders the localized not found page" do
    get "/404"

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("Página não encontrada")
  end

  it "answers JSON clients with a generic message" do
    get "/429", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to eq("error" => "Muitas tentativas")
  end
end
