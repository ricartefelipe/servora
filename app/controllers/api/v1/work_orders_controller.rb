# frozen_string_literal: true

module Api
  module V1
    # Work orders. Creation requires an Idempotency-Key header: retries with
    # the same key and body return the original response; the same key with a
    # different body is refused.
    class WorkOrdersController < BaseController
      FIELDS = %i[title problem_description customer_id service_location_id priority].freeze

      before_action(only: %i[index show]) { require_scope!("work_orders:read") }
      before_action(only: :create) { require_scope!("work_orders:write") }

      def index
        scope = updated_since(WorkOrder.order(:created_at, :id))
        status = params[:status].presence_in(WorkOrders::States.states) # rubocop:disable Rails/StrongParametersExpect -- optional filter
        scope = scope.where(status:) if status
        scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id].present?
        render_page(scope) { |order| Serializers.work_order(order) }
      end

      def show
        render json: { data: Serializers.work_order(WorkOrder.find(params.expect(:id))) }
      end

      def create
        key = request.headers["Idempotency-Key"].to_s
        raise ArgumentError, "o cabeçalho Idempotency-Key é obrigatório" unless key.match?(/\A[\w-]{8,100}\z/)

        attributes = params.expect(work_order: [*FIELDS, { equipment_ids: [] }])
        status, body = Api::IdempotentRequest.new(credential: current_credential, key:, request_body: attributes.to_h).call do
          [201, { data: Serializers.work_order(open_work_order(attributes)) }]
        end
        render json: body, status:
      end

      private

      def open_work_order(attributes)
        location = ServiceLocation.active.find(attributes[:service_location_id])
        unless location.customer_id == attributes[:customer_id]
          raise Servora::RuleViolation,
            "O local não pertence ao cliente informado."
        end

        fields = attributes.except(:equipment_ids).merge(origin: "internal", priority: attributes[:priority].presence || "normal")
        WorkOrders::Create.new(organization: Current.organization, actor: current_credential.created_by, attributes: fields,
          equipment_ids: Array(attributes[:equipment_ids])).call
      end
    end
  end
end
