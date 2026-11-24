# frozen_string_literal: true

class ContractServiceType < TenantRecord
  belongs_to :contract, inverse_of: :contract_service_types
  belongs_to :service_type
end
