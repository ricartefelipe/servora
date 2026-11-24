# frozen_string_literal: true

module Api
  module V1
    class ReceivablesController < BaseController
      before_action { require_scope!("receivables:read") }

      def index
        scope = updated_since(Receivable.order(:created_at, :id))
        status = params[:status].presence_in(Receivable::STATUSES.keys) # rubocop:disable Rails/StrongParametersExpect -- optional filter
        scope = scope.where(status:) if status
        render_page(scope) { |receivable| Serializers.receivable(receivable) }
      end
    end
  end
end
