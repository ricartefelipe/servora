# frozen_string_literal: true

# Sends generated documents and stored files with headers that keep them
# private and inert: no shared caching, no MIME sniffing, and a sandboxed
# content security policy for the file itself.
module FileDelivery
  extend ActiveSupport::Concern

  private

  def deliver_file(data, filename:, type:, inline: false)
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; sandbox"
    send_data data, filename:, type:, disposition: inline ? "inline" : "attachment"
  end
end
