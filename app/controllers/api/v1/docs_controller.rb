# frozen_string_literal: true

module Api
  module V1
    # OpenAPI description of the public API (no authentication required).
    class DocsController < ActionController::API
      def show
        send_file Rails.root.join("docs/api/openapi.yaml"), type: "application/yaml", disposition: "inline"
      end
    end
  end
end
