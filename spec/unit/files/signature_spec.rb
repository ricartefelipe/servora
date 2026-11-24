# frozen_string_literal: true

RSpec.describe Files::Signature do
  it "detects allowed formats by content, not by name" do
    expect(described_class.detect("\xFF\xD8\xFF\xE0rest")).to eq("image/jpeg")
    expect(described_class.detect("\x89PNG\r\n\x1A\nrest")).to eq("image/png")
    expect(described_class.detect("RIFF\x00\x00\x00\x00WEBPVP8")).to eq("image/webp")
    expect(described_class.detect("%PDF-1.7\n")).to eq("application/pdf")
  end

  it "rejects other contents" do
    ["MZ\x90\x00", "<svg xmlns=", "<html>", "GIF89a", "", nil].each do |head|
      expect(described_class.detect(head)).to be_nil
    end
  end

  it "builds safe file names with the extension of the detected type" do
    expect(described_class.safe_filename("../../Foto da obra (1).JPEG.exe", "image/png")).to eq("Foto-da-obra-1-.JPEG.png")
    expect(described_class.safe_filename("relatório técnico.pdf", "application/pdf")).to eq("relatório-técnico.pdf")
    expect(described_class.safe_filename(".htaccess", "image/jpeg")).to eq("arquivo.jpg")
  end
end
