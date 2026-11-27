# frozen_string_literal: true

# Display-only formatting of values kept raw in the database.
module FormattingHelper
  # Brazilian phone mask for display only; stored values are left as typed.
  def format_phone(value)
    Documents::BrazilianPhone.format(value).presence
  end

  # A code such as "OS-2026-00042" that may wrap only after its hyphens (line
  # breaking rules never break "-2026" on their own), so a narrow box shows
  # whole segments instead of clipping it.
  def breakable_code(code)
    safe_join(code.to_s.split(/(?<=-)/), tag.wbr)
  end
end
