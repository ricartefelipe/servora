# frozen_string_literal: true

module Field
  # JSON endpoint for field operations (online submissions and the offline
  # queue). Every request re-checks access to the work order; the response is
  # the stored outcome of the operation id.
  class OperationsController < TenantController
    rate_limit to: 120, within: 1.minute, by: -> { current_membership&.id || request.remote_ip }

    def create
      attributes = params.expect(operation: [:id, :kind, :version, :work_order_id, { payload: {} }])
      work_order = policy_scope(tenant_relation(WorkOrder)).includes(:assignments).find(attributes[:work_order_id])
      authorize work_order, :update_execution?
      render json: Field::Sync.new(work_order:, membership: current_membership, operation: operation(attributes)).call
    rescue ActionController::ParameterMissing, ArgumentError
      render json: { status: "rejected", result: { error: "Operação malformada." } }, status: :unprocessable_content
    end

    private

    def operation(attributes)
      id = attributes[:id].to_s
      raise ArgumentError, "invalid operation id" unless Servora::Tenancy::UUID_FORMAT.match?(id)

      Field::Sync::Operation.new(id:, kind: attributes[:kind].to_s, version: attributes[:version].presence,
        payload: attributes[:payload].to_h)
    end
  end
end
