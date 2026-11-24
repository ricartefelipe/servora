# frozen_string_literal: true

module WorkOrders
  # Bulk status change from the work-order list. Every selected order goes
  # through the same policy predicate and use case as the single change on
  # the order page; the summary names the orders that could not be moved.
  class BulkStatusesController < TenantController
    LISTED_FAILURES = 10
    RETURN_PARAMS = %i[situacao q pagina].freeze

    def create
      authorize WorkOrder, :bulk_change_status?
      change = params.expect(status_change: %i[to reason])
      result = WorkOrders::BulkChangeStatus.new(
        scope: policy_scope(tenant_relation(WorkOrder)), ids: selected_ids, to: change[:to], reason: change[:reason],
        actor: current_membership,
        authorize: ->(work_order) { policy(work_order).change_status? }
      ).call
      redirect_to return_path, status: :see_other, **summary(result)
    rescue Servora::RuleViolation => e
      redirect_to return_path, alert: e.message, status: :see_other
    end

    private

    # Checkbox values (work_order_ids[]); anything other than a list is ignored.
    def selected_ids
      ids = params[:work_order_ids]
      ids.is_a?(Array) ? ids : []
    end

    # The list comes back with the filters and page it was submitted from.
    def return_path
      filters = params[:retorno]
      filters = filters.is_a?(ActionController::Parameters) ? filters.permit(*RETURN_PARAMS).to_h.compact_blank : {}
      work_orders_path(filters)
    end

    # "8 ordens atualizadas para Em execução; 2 não puderam ser alteradas: OS-0012 (situação não permite), …".
    # Any refusal is an alert, which stays on screen until dismissed.
    def summary(result)
      updated = result.updated.size
      return { alert: nothing_changed(result.failed) } if updated.zero?

      count = updated == 1 ? "1 ordem atualizada" : "#{updated} ordens atualizadas"
      moved = "#{count} para #{WorkOrders::LABELS[result.to]}"
      return { notice: "#{moved}." } unless result.any_failed?

      verb = result.failed.one? ? "não pôde ser alterada" : "não puderam ser alteradas"
      { alert: "#{moved}; #{result.failed.size} #{verb}: #{refused_list(result.failed)}." }
    end

    def nothing_changed(failures)
      failures.empty? ? "Nenhuma ordem foi alterada." : "Nenhuma ordem foi alterada: #{refused_list(failures)}."
    end

    def refused_list(failures)
      listed = failures.first(LISTED_FAILURES).map { |failure| "#{failure.work_order.number} (#{failure.reason})" }
      listed << "e mais #{failures.size - LISTED_FAILURES}" if failures.size > LISTED_FAILURES
      listed.join(", ")
    end
  end
end
