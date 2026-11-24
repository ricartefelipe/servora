# frozen_string_literal: true

module Contracts
  class PlansController < TenantController
    FIELDS = %i[title service_location_id service_type_id priority frequency_unit frequency_interval schedule_mode
                anchor_date lead_days instructions active].freeze

    before_action :load_contract
    before_action :load_plan, only: %i[show edit update generate]

    def show
      authorize @plan
      @occurrences = tenant_relation(MaintenanceOccurrence).where(maintenance_plan_id: @plan.id).includes(:work_order)
        .order(sequence: :desc).limit(50)
      @upcoming = @plan.after_completion? ? [] : @plan.schedule.upcoming([@plan.next_sequence, @plan.anchor_sequence].max, 6)
    end

    def new
      authorize @contract, :add_plan?
      @plan = MaintenancePlan.new(contract: @contract, frequency_unit: "month", frequency_interval: 1, lead_days: 7,
        anchor_date: [@contract.starts_on, Time.zone.today].max, priority: "normal", schedule_mode: "calendar")
      load_form_options
    end

    def edit
      authorize @plan, :update?
      load_form_options
    end

    def create
      authorize @contract, :add_plan?
      plan = save_plan(nil)
      redirect_to contract_plan_path(@contract, plan), notice: "Plano preventivo criado.", status: :see_other
    rescue ActiveRecord::RecordInvalid, Servora::RuleViolation => e
      invalid(:new, e)
    end

    def update
      authorize @plan, :update?
      save_plan(@plan)
      redirect_to contract_plan_path(@contract, @plan), notice: "Plano atualizado. Ocorrências já geradas foram mantidas.",
        status: :see_other
    rescue ActiveRecord::RecordInvalid, Servora::RuleViolation => e
      invalid(:edit, e)
    end

    def generate
      authorize @plan
      occurrences = Preventive::GenerateOccurrences.new(plan: @plan).call
      notice = occurrences.empty? ? "Nenhuma ocorrência pendente." : "#{occurrences.size} ocorrência(s) gerada(s)."
      redirect_to contract_plan_path(@contract, @plan), notice:, status: :see_other
    end

    private

    def load_contract
      @contract = policy_scope(tenant_relation(Contract)).find(params.expect(:contract_id))
    end

    def load_plan
      @plan = tenant_relation(MaintenancePlan).where(contract_id: @contract.id).find(params.expect(:id))
    end

    def save_plan(plan)
      attributes = params.expect(maintenance_plan: [*FIELDS, { equipment_ids: [] }])
      Preventive::SavePlan.new(contract: @contract, plan:, actor: current_membership,
        attributes: attributes.except(:equipment_ids), equipment_ids: attributes[:equipment_ids]).call
    end

    def invalid(template, error)
      @plan = invalid_record(error)
      flash.now[:alert] = error.message if error.is_a?(Servora::RuleViolation)
      load_form_options
      render template, status: :unprocessable_content
    end

    def invalid_record(error)
      return error.record if error.respond_to?(:record) && error.record.is_a?(MaintenancePlan)

      @plan || MaintenancePlan.new(contract: @contract, **params.expect(maintenance_plan: FIELDS).to_h.symbolize_keys)
    end

    def load_form_options
      @locations = tenant_relation(ServiceLocation).where(customer_id: @contract.customer_id).active.alphabetical
      @equipment = tenant_relation(Equipment).where(customer_id: @contract.customer_id).active.order(:equipment_type,
        :serial_number)
      @service_types = tenant_relation(ServiceType).active.alphabetical
    end
  end
end
