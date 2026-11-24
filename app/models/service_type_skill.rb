# frozen_string_literal: true

class ServiceTypeSkill < TenantRecord
  belongs_to :service_type
  belongs_to :skill
end
