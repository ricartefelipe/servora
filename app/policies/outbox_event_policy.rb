# frozen_string_literal: true

class OutboxEventPolicy < ApplicationPolicy
  def index? = can?(:outbox_reprocess) || can?(:integrations_manage)
  def show? = index?
  def reprocess? = can?(:outbox_reprocess) && record.dead?

  class Scope < Scope
    def resolve
      can?(:outbox_reprocess) || can?(:integrations_manage) ? scope.all : scope.none
    end
  end
end
