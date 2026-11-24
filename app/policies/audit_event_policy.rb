# frozen_string_literal: true

class AuditEventPolicy < ApplicationPolicy
  def index? = can?(:audit_view)

  class Scope < Scope
    def resolve
      can?(:audit_view) ? scope.all : scope.none
    end
  end
end
