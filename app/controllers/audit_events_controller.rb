# frozen_string_literal: true

class AuditEventsController < TenantController
  def index
    authorize AuditEvent
    scope = policy_scope(current_organization.audit_events).recent_first
    scope = scope.where(action: params[:acao]) if params[:acao].present?
    @actions = policy_scope(current_organization.audit_events).distinct.order(:action).pluck(:action)
    @pagination = Pagination.new(scope, page: params[:pagina])
  end
end
