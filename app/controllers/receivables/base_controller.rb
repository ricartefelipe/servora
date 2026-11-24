# frozen_string_literal: true

module Receivables
  class BaseController < TenantController
    include ModalForms

    before_action :load_receivable

    rescue_from Servora::RuleViolation do |error|
      redirect_to receivable_path(@receivable), alert: error.message, status: :see_other
    end

    private

    def load_receivable
      @receivable = policy_scope(tenant_relation(Receivable)).find(params.expect(:receivable_id))
    end

    def back(notice) = redirect_to(receivable_path(@receivable), notice:, status: :see_other)
  end
end
