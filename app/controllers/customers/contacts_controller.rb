# frozen_string_literal: true

module Customers
  class ContactsController < TenantController
    include ModalForms

    before_action :load_customer
    before_action :load_contact, only: %i[edit update archive]

    def new
      @contact = @customer.contacts.new(organization: current_organization)
      authorize @contact, :create?
    end

    def edit; end

    def create
      @contact = @customer.contacts.new(contact_params.merge(organization: current_organization))
      authorize @contact, :create?
      if @contact.save
        AuditEvent.record!(action: "customer_contact.created", auditable: @contact, changes: { name: @contact.name })
        redirect_to customer_path(@customer, anchor: "contatos"), notice: "Contato adicionado.", status: :see_other
      else
        render_invalid_form(partial: "customers/contacts/form", template: :new, customer: @customer, contact: @contact)
      end
    end

    def update
      if @contact.update(contact_params)
        AuditEvent.record!(action: "customer_contact.updated", auditable: @contact,
          changes: @contact.saved_changes.except("updated_at"))
        redirect_to customer_path(@customer, anchor: "contatos"), notice: "Contato atualizado.", status: :see_other
      else
        render_invalid_form(partial: "customers/contacts/form", template: :edit, customer: @customer, contact: @contact)
      end
    end

    def archive
      @contact.update!(archived_at: Time.current, portal_enabled: false)
      AuditEvent.record!(action: "customer_contact.archived", auditable: @contact)
      redirect_to customer_path(@customer, anchor: "contatos"), notice: "Contato arquivado.", status: :see_other
    end

    private

    def load_customer
      @customer = policy_scope(tenant_relation(Customer)).find(params.expect(:customer_id))
    end

    def load_contact
      @contact = tenant_relation(CustomerContact).where(customer_id: @customer.id).find(params.expect(:id))
      authorize @contact, :"#{action_name == "edit" ? "update" : action_name}?"
    end

    def contact_params
      params.expect(customer_contact: %i[name email phone position can_approve can_follow portal_enabled])
    end
  end
end
