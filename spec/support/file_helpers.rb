# frozen_string_literal: true

module FileHelpers
  PNG = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00".b

  def uploaded(content, filename, content_type = "application/octet-stream")
    Rack::Test::UploadedFile.new(StringIO.new(content.b), content_type, true, original_filename: filename)
  end

  def png_upload(filename = "antes.png") = uploaded(PNG, filename, "image/png")

  def pdf_text(binary)
    require "pdf-reader"
    PDF::Reader.new(StringIO.new(binary)).pages.map(&:text).join("\n")
  end
end

RSpec.configure do |config|
  config.include FileHelpers
end
