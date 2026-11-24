# frozen_string_literal: true

class MembershipSkill < TenantRecord
  belongs_to :membership
  belongs_to :skill
end
