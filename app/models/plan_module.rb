# frozen_string_literal: true

# Add-on module of the platform (reference data).
class PlanModule < ApplicationRecord
  scope :ordered, -> { order(:position) }

  def readonly? = true

  def self.price_table = ordered.pluck(:code, :monthly_price).to_h
  def self.names = ordered.pluck(:code, :name).to_h
end
