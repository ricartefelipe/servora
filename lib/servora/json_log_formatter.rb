# frozen_string_literal: true

require "json"
require "time"

module Servora
  # Logger formatter for LOG_FORMAT=json: one JSON object per line. Messages
  # already built as JSON (Servora::StructuredLog) keep their fields with the
  # level added; any other message is wrapped in a "message" field.
  class JsonLogFormatter
    def call(severity, time, _progname, message)
      "#{JSON.generate({ "time" => time.utc.iso8601(3), "level" => severity }.merge(fields(message)))}\n"
    end

    private

    def fields(message)
      text = message.is_a?(String) ? message : message.inspect
      return { "message" => text.strip } unless text.start_with?("{")

      parsed = JSON.parse(text)
      parsed.is_a?(Hash) ? parsed : { "message" => text.strip }
    rescue JSON::ParserError
      { "message" => text.strip }
    end
  end
end
