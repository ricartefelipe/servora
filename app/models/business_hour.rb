# frozen_string_literal: true

# Opening interval of the organization on a weekday ([start, end) minutes from
# local midnight; weekday follows Date#wday).
class BusinessHour < TenantRecord
  WEEKDAYS = %w[Domingo Segunda Terça Quarta Quinta Sexta Sábado].freeze

  validates :weekday, inclusion: { in: 0..6 }
  validates :start_minute, numericality: { only_integer: true, in: 0..1439 }
  validates :end_minute, numericality: { only_integer: true, in: 1..1440 }
  validate :ordered

  def self.clock(minute) = format("%<hour>02d:%<minute>02d", hour: minute / 60, minute: minute % 60)

  def label = "#{self.class.clock(start_minute)}–#{self.class.clock(end_minute)}"

  private

  def ordered
    errors.add(:end_minute, "deve ser posterior ao início") if start_minute && end_minute && end_minute <= start_minute
  end
end
