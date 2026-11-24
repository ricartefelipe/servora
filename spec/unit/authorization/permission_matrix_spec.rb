# frozen_string_literal: true

RSpec.describe Authorization::PermissionMatrix do
  it "has a Portuguese label for every permission" do
    expect(described_class::LABELS.keys).to match_array(Authorization::Permissions::ALL)
  end

  it "is reproduced verbatim in docs/ARQUITETURA.md" do
    document = File.read(File.expand_path("../../../docs/ARQUITETURA.md", __dir__))

    expect(document).to include(described_class.markdown)
  end
end
