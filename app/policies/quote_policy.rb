# frozen_string_literal: true

class QuotePolicy < ApplicationPolicy
  def index? = can?(:quotes_view)
  def show? = index?
  def create? = can?(:quotes_manage)
  def edit_draft? = can?(:quotes_manage) && record.editable?
  def send_version? = edit_draft?
  def new_version? = can?(:quotes_manage) && !record.closed? && record.current_version.present? && !record.current_version.draft?
  def register_decision? = can?(:quotes_manage) && record.sent? && record.current_version&.sent?
  def send_portal_link? = register_decision?
  def cancel? = can?(:quotes_manage) && !record.closed?
  def convert? = can?(:work_orders_manage) && (record.approved? || record.converted?)
  def view_costs? = can?(:costs_view)

  class Scope < Scope
    def resolve
      can?(:quotes_view) ? scope.all : scope.none
    end
  end
end
