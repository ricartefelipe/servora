# frozen_string_literal: true

require "rails_helper"

# Scans app/ for every AuditEvent.record! call and fails when an action key it
# can record has no pt-BR label in Audit::Labels. Interpolated keys
# ("quote.#{@decision}") must be declared in dynamic_suffixes below.
RSpec.describe Audit::Labels do
  def dynamic_suffixes
    {
      "contract." => Contract::STATUSES.keys - ["draft"],
      "equipment." => %w[archived restored relocated ownership_transferred],
      "payment_refund." => %w[accepted failed unknown] + Payments::ResolveRefund::ACTIONS,
      "quote." => Quotes::Decide::DECISIONS,
      "service_invoice." => ServiceInvoice::STATUSES.keys,
      "webhook_endpoint." => %w[enabled disabled],
      "work_order.item_" => %w[authorized rejected]
    }
  end

  # Source of each AuditEvent.record!(...) call, with balanced parentheses.
  def record_calls
    Rails.root.glob("app/**/*.rb").flat_map do |path|
      source = path.read
      source.to_enum(:scan, /AuditEvent\.record!\(/).map do
        start = Regexp.last_match.end(0) - 1
        ["#{path.relative_path_from(Rails.root)}:#{source[0, start].count("\n") + 1}", balanced(source, start)]
      end
    end
  end

  def balanced(source, start)
    depth = 0
    source[start..].each_char.with_index do |char, step|
      depth += 1 if char == "("
      depth -= 1 if char == ")"
      return source[start, step + 1] if depth.zero?
    end
    source[start..]
  end

  def action_expression(call)
    call[/\A\(\s*action:\s*(.+?),\s*(?:organization|auditable|changes|metadata):/m, 1] ||
      call[/\A\(\s*action:\s*(.+?)\s*\)\z/m, 1]
  end

  # { "file:line" => [keys] }; unreadable calls map to nil.
  def recorded_actions
    record_calls.to_h do |location, call|
      expression = action_expression(call).to_s
      literals = expression.scan(/"([a-z_]+\.[a-z_]+)"/).flatten
      dynamic = expression.scan(/"([a-z_]+\.[a-z_]*)#\{/).flatten.map do |prefix|
        dynamic_suffixes.fetch(prefix) { raise KeyError, "#{location}: declare the values of \"#{prefix}…\" in this spec" }
          .map { |suffix| "#{prefix}#{suffix}" }
      end
      keys = literals + dynamic.flatten
      [location, keys.presence]
    end
  end

  it "finds the audit calls of the application" do
    expect(record_calls.size).to be > 60
  end

  it "reads the action of every audit call" do
    expect(recorded_actions.select { |_location, keys| keys.nil? }.keys).to be_empty
  end

  it "has a pt-BR label for every action key recorded in app/" do
    missing = recorded_actions.flat_map do |location, keys|
      Array(keys).reject { |key| described_class.known?(key) }.map { |key| "#{location}: #{key}" }
    end

    expect(missing).to be_empty
  end
end
