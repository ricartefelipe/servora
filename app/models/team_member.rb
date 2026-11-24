# frozen_string_literal: true

class TeamMember < TenantRecord
  belongs_to :team
  belongs_to :membership
end
