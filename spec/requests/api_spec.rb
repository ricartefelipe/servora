# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public API v1" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:owner) { create(:membership, :owner, organization:) }
  let(:token) { api_token(owner) }

  it "authenticates with revocable, expiring credentials" do
    get api_v1_customers_path
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq("unauthorized")

    get api_v1_customers_path, headers: api_headers(token)
    expect(response).to have_http_status(:ok)

    in_tenant(organization) { ApiCredential.sole.update!(revoked_at: Time.current) }
    get api_v1_customers_path, headers: api_headers(token)
    expect(response).to have_http_status(:unauthorized)
  end

  it "enforces scopes" do
    limited = api_token(owner, scopes: ["customers:read"])

    get api_v1_work_orders_path, headers: api_headers(limited)

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig("error", "code")).to eq("insufficient_scope")
  end

  it "never returns data of another organization" do
    other = create(:customer, organization: create(:organization))

    get api_v1_customer_path(other), headers: api_headers(token)
    expect(response).to have_http_status(:not_found)

    get api_v1_customers_path, headers: api_headers(token)
    expect(response.parsed_body["data"].pluck("id")).to eq([scenario[:customer].id])
  end

  it "paginates with a hard limit and filters by update time" do
    create_list(:customer, 2, organization:)

    get api_v1_customers_path(page: { size: 1000 }), headers: api_headers(token)
    expect(response.parsed_body["meta"]).to include("per_page" => 100, "next_page" => nil)

    get api_v1_customers_path(page: { size: 1 }), headers: api_headers(token)
    expect(response.parsed_body["meta"]).to include("per_page" => 1, "next_page" => 2)

    get api_v1_customers_path(updated_since: 1.minute.from_now.iso8601), headers: api_headers(token)
    expect(response.parsed_body["data"]).to be_empty

    get api_v1_customers_path(updated_since: "ontem"), headers: api_headers(token)
    expect(response).to have_http_status(:bad_request)
  end

  it "lists work orders, equipment and receivables without internal costs" do
    open_work_order(scenario)

    get api_v1_work_orders_path(status: "approved"), headers: api_headers(token)
    expect(response.parsed_body["data"].first).to include("status" => "approved").and(satisfy { |row| !row.key?("unit_cost") })

    get api_v1_equipment_index_path(customer_id: scenario[:customer].id), headers: api_headers(token)
    expect(response.parsed_body["data"].size).to eq(1)
    get api_v1_receivables_path, headers: api_headers(token)
    expect(response).to have_http_status(:ok)
  end

  describe "POST /api/v1/work_orders" do
    let(:body) do
      { work_order: { title: "Integração ERP", problem_description: "Chamado aberto pelo ERP do cliente.",
                      customer_id: scenario[:customer].id, service_location_id: scenario[:location].id } }
    end

    it "requires an Idempotency-Key and replays the original response" do
      post api_v1_work_orders_path, params: body, headers: api_headers(token), as: :json
      expect(response).to have_http_status(:bad_request)

      2.times do
        post api_v1_work_orders_path, params: body, headers: api_headers(token, "Idempotency-Key" => "erp-000123"), as: :json
      end

      expect(response).to have_http_status(:created)
      expect(in_tenant(organization) { WorkOrder.where(title: "Integração ERP").count }).to eq(1)
      body[:work_order][:title] = "Outro conteúdo"
      post api_v1_work_orders_path, params: body, headers: api_headers(token, "Idempotency-Key" => "erp-000123"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a location of another customer" do
      body[:work_order][:service_location_id] = create(:service_location, customer: create(:customer, organization:)).id

      post api_v1_work_orders_path, params: body, headers: api_headers(token, "Idempotency-Key" => "erp-000124"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "documents every public route in the OpenAPI description" do
    get api_v1_openapi_path
    spec = YAML.safe_load(response.body)

    documented = spec["paths"].flat_map do |path, operations|
      operations.keys.map do |verb|
        "#{verb.upcase} /api/v1#{path.gsub(/\{(\w+)\}/, ':\1')}"
      end
    end
    routed = Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.delete_suffix("(.:format)")
      "#{route.verb} #{path}" if path.start_with?("/api/v1/") && !path.end_with?("/openapi")
    end
    expect(documented).to match_array(routed)
  end
end
