# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Health probes" do
  describe "GET /up" do
    it "reports liveness without touching dependencies" do
      allow(ActiveRecord::Base).to receive(:connection_pool).and_call_original

      get "/up"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "ok", "version" => Servora::VERSION)
      expect(ActiveRecord::Base).not_to have_received(:connection_pool)
    end
  end

  describe "GET /ready" do
    it "reports ready when the primary database answers and is migrated" do
      get "/ready"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("checks", "primary", "ok")).to be(true)
    end

    it "returns 503 without leaking connection details when a database fails" do
      allow(ActiveRecord::Base.connection_pool).to receive(:with_connection)
        .and_raise(ActiveRecord::ConnectionNotEstablished, "host=db.internal password=secret")

      get "/ready"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("checks", "primary")).to include("ok" => false, "error" => "ActiveRecord::ConnectionNotEstablished")
      expect(response.body).not_to include("secret")
    end
  end
end
