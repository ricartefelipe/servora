# frozen_string_literal: true

module Contracts
  # Creates a contract (draft, version 1) or revises its terms. Every revision
  # that changes the terms stores a new append-only version with its reason;
  # revisions of contracts in force require a reason. Ended contracts are
  # immutable.
  class Save
    def initialize(organization:, attributes:, actor:, contract: nil, service_type_ids: [], reason: nil)
      @organization = organization
      @contract = contract
      @attributes = attributes.to_h.symbolize_keys.slice(*Contract::TERM_FIELDS.map(&:to_sym), :customer_id)
      @service_type_ids = Array(service_type_ids).compact_blank.uniq
      @actor = actor
      @reason = reason.to_s.strip.presence
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) { @contract ? revise : create }
    end

    private

    def create
      contract = @organization.contracts.new(@attributes.merge(
        number: Numbering.next!(organization: @organization, scope: "contract"), status: "draft", created_by: @actor
      ))
      contract.save!
      replace_service_types(contract)
      store_version(contract, 1, @reason || "Versão inicial")
      AuditEvent.record!(action: "contract.created", auditable: contract, changes: { number: contract.number })
      contract
    end

    def revise
      @contract.lock!
      raise Errors::Invalid, "Contratos encerrados não podem ser alterados." if @contract.ended?

      before = @contract.terms
      @contract.update!(@attributes.except(:customer_id))
      replace_service_types(@contract)
      return @contract if @contract.terms == before

      # Raising rolls back the savepoint: no change is kept without a reason.
      raise Errors::Invalid, "Informe o motivo da alteração." if @reason.nil? && @contract.status != "draft"

      @contract.update!(current_version: @contract.current_version + 1)
      store_version(@contract, @contract.current_version, @reason)
      AuditEvent.record!(action: "contract.revised", auditable: @contract,
        changes: { version: @contract.current_version, reason: @reason })
      @contract
    end

    def replace_service_types(contract)
      ids = ServiceType.where(id: @service_type_ids).pluck(:id)
      ContractServiceType.where(contract_id: contract.id).where.not(service_type_id: ids).delete_all
      (ids - ContractServiceType.where(contract_id: contract.id).pluck(:service_type_id)).each do |service_type_id|
        ContractServiceType.create!(organization_id: contract.organization_id, contract:, service_type_id:)
      end
      contract.contract_service_types.reset
    end

    def store_version(contract, number, reason)
      ContractVersion.create!(organization_id: contract.organization_id, contract:, version_number: number,
        terms: contract.terms.as_json, reason:, created_by_membership_id: @actor&.id)
    end
  end
end
