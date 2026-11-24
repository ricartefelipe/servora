# frozen_string_literal: true

class InvitationPolicy < ApplicationPolicy
  def index? = can?(:members_view)
  def create? = can?(:members_manage) && (record.role != "owner" || membership.owner?)
  def destroy? = can?(:members_manage) && record.usable? && (record.role != "owner" || membership.owner?)

  class Scope < Scope
    def resolve
      can?(:members_view) ? scope.all : scope.none
    end
  end
end
