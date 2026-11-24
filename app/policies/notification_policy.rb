# frozen_string_literal: true

# Members only ever see and update their own notifications.
class NotificationPolicy < ApplicationPolicy
  def index? = membership.present?
  def update? = record.recipient_membership_id == membership.id

  class Scope < Scope
    def resolve
      scope.where(recipient_membership_id: membership.id)
    end
  end
end
