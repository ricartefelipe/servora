# frozen_string_literal: true

module Portal
  # Service requests and work orders of the contact's customer: status,
  # upcoming visits and execution reports. Internal notes, costs and prices
  # of additional items are never shown.
  class WorkOrdersController < BaseController
    rate_limit to: 5, within: 1.hour, only: :create, name: "portal-request",
      with: -> { redirect_to portal_work_orders_path, alert: "Muitos chamados em pouco tempo. Tente novamente mais tarde." }

    def index
      @open = params[:situacao] != "encerradas"
      scope = customer_scope(WorkOrder).includes(:service_location).order(requested_at: :desc)
      @work_orders = (@open ? scope.open_work : scope.where(status: WorkOrders::TERMINAL_STATES)).limit(100)
    end

    def show
      @work_order = customer_scope(WorkOrder).includes(:service_location, :equipment).find(params.expect(:id))
      @visits = Visit.where(work_order_id: @work_order.id).where.not(status: "canceled").order(:scheduled_start)
      @reports = WorkOrderReport.where(work_order_id: @work_order.id).order(version_number: :desc)
    end

    def new
      load_options
    end

    def create
      attributes = params.expect(request: %i[title description service_location_id equipment_id urgency])
      work_order = Portal::OpenRequest.new(contact: current_contact, **attributes.to_h.symbolize_keys).call
      redirect_to portal_work_order_path(work_order), notice: "Chamado #{work_order.number} aberto. Nossa equipe vai analisar.",
        status: :see_other
    rescue Servora::RuleViolation => e
      flash.now[:alert] = e.message
      @request_values = attributes
      load_options
      render :new, status: :unprocessable_content
    end

    private

    def load_options
      @locations = customer_scope(ServiceLocation).active.alphabetical
      @equipment = customer_scope(Equipment).active.order(:equipment_type)
    end
  end
end
