# frozen_string_literal: true

# Field area (headless policy): available to members who execute work orders.
class FieldPolicy < ApplicationPolicy
  def show? = can?(:work_orders_execute)
end
