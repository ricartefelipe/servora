# frozen_string_literal: true

class ApiIdempotencyKey < TenantRecord
  belongs_to :api_credential
end
