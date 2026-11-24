# frozen_string_literal: true

class WorkSchedule < TenantRecord
  WEEKDAYS = %w[Domingo Segunda Terça Quarta Quinta Sexta Sábado].freeze

  belongs_to :membership

  validates :weekday, inclusion: { in: 0..6 }
  validates :start_minute, numericality: { only_integer: true, in: 0..1439 }
  validates :end_minute, numericality: { only_integer: true, in: 1..1440 }
  validate :start_before_end

  def slot = Scheduling::WorkingHours::Slot.new(weekday, start_minute, end_minute)
  def label = "#{WEEKDAYS.fetch(weekday)} #{format_minute(start_minute)}–#{format_minute(end_minute)}"

  private

  def format_minute(minute) = format("%<h>02d:%<m>02d", h: minute / 60, m: minute % 60)

  def start_before_end
    errors.add(:end_minute, "deve ser posterior ao início") if start_minute && end_minute && start_minute >= end_minute
  end
end
