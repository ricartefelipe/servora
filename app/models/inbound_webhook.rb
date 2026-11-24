# frozen_string_literal: true

# Notification received from a provider, stored before acknowledgement and
# processed asynchronously (deduplicated by the provider's event id).
class InboundWebhook < TenantRecord
end
