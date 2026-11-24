# frozen_string_literal: true

class VisitTransition < TenantRecord
  belongs_to :visit, inverse_of: :transitions

  def readonly? = persisted?
end
