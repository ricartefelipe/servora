# frozen_string_literal: true

# What Pundit policies receive as "user": the person and, inside an
# organization, the active membership that defines the permissions.
PolicyContext = Data.define(:user, :membership) do
  def organization = membership&.organization

  def can?(permission)
    membership.present? && membership.can?(permission)
  end

  def technician?
    membership&.technician? || false
  end
end
