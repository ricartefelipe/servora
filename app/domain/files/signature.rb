# frozen_string_literal: true

module Files
  # Content type detection by file signature ("magic bytes"). The browser's
  # declared type and the file extension are never trusted.
  module Signature
    ALLOWED = {
      "image/jpeg" => { kind: "photo", extension: "jpg" },
      "image/png" => { kind: "photo", extension: "png" },
      "image/webp" => { kind: "photo", extension: "webp" },
      "application/pdf" => { kind: "document", extension: "pdf" }
    }.freeze

    module_function

    # Returns the detected content type among the allowed ones, or nil.
    def detect(head)
      bytes = head.to_s.b
      return "image/jpeg" if bytes.start_with?("\xFF\xD8\xFF".b)
      return "image/png" if bytes.start_with?("\x89PNG\r\n\x1A\n".b)
      return "image/webp" if bytes[0, 4] == "RIFF" && bytes[8, 4] == "WEBP"
      return "application/pdf" if bytes.start_with?("%PDF-")

      nil
    end

    # Keeps letters (accents included), digits, dot, dash and underscore; the
    # extension always matches the detected type.
    def safe_filename(original, content_type)
      base = File.basename(original.to_s).sub(/\.[^.]*\z/, "").gsub(/[^\p{L}\p{N}._-]+/, "-").gsub(/-{2,}/, "-")
      base = base.delete_prefix(".").first(80).presence || "arquivo"
      "#{base}.#{ALLOWED.fetch(content_type)[:extension]}"
    end
  end
end
