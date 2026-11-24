# frozen_string_literal: true

module Customers
  class LocationsController < TenantController
    include ModalForms

    before_action :load_customer
    before_action :load_location, only: %i[edit update archive]

    def new
      @location = @customer.service_locations.new(organization: current_organization)
      authorize @location, :create?
    end

    def edit; end

    def create
      @location = @customer.service_locations.new(location_params.merge(organization: current_organization))
      authorize @location, :create?
      if @location.save
        AuditEvent.record!(action: "service_location.created", auditable: @location, changes: { name: @location.name })
        redirect_to customer_path(@customer, anchor: "locais"), notice: "Local de atendimento adicionado.", status: :see_other
      else
        render_invalid_form(partial: "customers/locations/form", template: :new, customer: @customer, location: @location)
      end
    end

    def update
      if @location.update(location_params)
        AuditEvent.record!(action: "service_location.updated", auditable: @location,
          changes: @location.saved_changes.except("updated_at"))
        redirect_to customer_path(@customer, anchor: "locais"), notice: "Local atualizado.", status: :see_other
      else
        render_invalid_form(partial: "customers/locations/form", template: :edit, customer: @customer, location: @location)
      end
    end

    def archive
      @location.update!(archived_at: Time.current)
      AuditEvent.record!(action: "service_location.archived", auditable: @location)
      redirect_to customer_path(@customer, anchor: "locais"), notice: "Local arquivado.", status: :see_other
    end

    # Location <select> for the equipment form, reloaded when the customer changes.
    def options
      authorize @customer, :show?
      @locations = @customer.service_locations.active.alphabetical
      render layout: false
    end

    private

    def load_customer
      @customer = policy_scope(tenant_relation(Customer)).find(params.expect(:customer_id))
    end

    def load_location
      @location = tenant_relation(ServiceLocation).where(customer_id: @customer.id).find(params.expect(:id))
      authorize @location, :"#{action_name == "edit" ? "update" : action_name}?"
    end

    def location_params
      params.expect(service_location: %i[name street number complement district city state postal_code access_instructions])
    end
  end
end
