# frozen_string_literal: true

module Api
  module V1
    class CustomersController < BaseController
      before_action { require_scope!("customers:read") }

      def index
        scope = updated_since(Customer.order(:created_at, :id))
        render_page(scope) { |customer| Serializers.customer(customer) }
      end

      def show
        render json: { data: Serializers.customer(Customer.find(params.expect(:id))) }
      end
    end
  end
end
