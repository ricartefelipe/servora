# frozen_string_literal: true

class OutboxEventsController < TenantController
  STATUS_FILTERS = %w[dead pending processing processed].freeze

  def index
    authorize OutboxEvent
    scope = policy_scope(current_organization.outbox_events).recent_first
    @status = params[:situacao].presence_in(STATUS_FILTERS) # rubocop:disable Rails/StrongParametersExpect -- optional filter
    scope = @status ? scope.where(status: @status) : scope.attention
    @pagination = Pagination.new(scope, page: params[:pagina])
    @counts = policy_scope(current_organization.outbox_events).group(:status).count
  end

  def show
    @event = policy_scope(current_organization.outbox_events).find(params.expect(:id))
    authorize @event
    @failures = @event.failures.recent_first.limit(50)
  end

  def reprocess
    @event = policy_scope(current_organization.outbox_events).find(params.expect(:id))
    authorize @event
    Outbox::Reprocess.new(event: @event).call
    redirect_to outbox_event_path(@event), notice: "Evento reenviado para processamento."
  rescue Servora::RuleViolation => e
    redirect_to outbox_event_path(@event), alert: e.message
  end
end
