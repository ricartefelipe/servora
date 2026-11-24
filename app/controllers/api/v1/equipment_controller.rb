# frozen_string_literal: true

module Api
  module V1
    class EquipmentController < BaseController
      before_action { require_scope!("equipment:read") }

      def index
        scope = updated_since(Equipment.order(:created_at, :id))
        scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id].present?
        render_page(scope) { |item| Serializers.equipment(item) }
      end
    end
  end
end
