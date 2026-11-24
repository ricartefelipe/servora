# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Work order evidences" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:technician) { scenario[:technician] }
  let!(:work_order) { open_work_order(scenario) }

  before { in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: technician).call } }

  def upload(file, caption: nil)
    post work_order_evidences_path(work_order), params: { evidence: { file:, caption: } }
  end

  it "lets the assigned technician upload a photo served inline with private headers" do
    sign_in_as(technician)

    upload(png_upload("../Foto antes.png"), caption: "Antes da limpeza")
    evidence = in_tenant(organization) { WorkOrderEvidence.sole }
    get work_order_evidence_path(work_order, evidence)

    expect(response.body.b).to eq(FileHelpers::PNG)
    expect(response.headers).to include("Content-Type" => "image/png", "Cache-Control" => "private, no-store",
      "X-Content-Type-Options" => "nosniff")
    expect(response.headers["Content-Disposition"]).to start_with("inline").and include("Foto-antes.png")
    expect(evidence).to have_attributes(kind: "photo", caption: "Antes da limpeza")
  end

  it "rejects files whose content is not an allowed format, whatever the name or declared type" do
    sign_in_as(technician)

    upload(uploaded("MZ\x90\x00 executável", "foto.jpg", "image/jpeg"))
    follow_redirect!

    expect(response.body).to include("Formato não aceito")
    expect(in_tenant(organization) { [WorkOrderEvidence.count, ActiveStorage::Blob.count] }).to eq([0, 0])
  end

  it "enforces the size limit" do
    sign_in_as(technician)
    stub_const("Evidences::Upload::MAX_BYTES", 10)

    upload(png_upload)
    follow_redirect!

    expect(response.body).to include("excede o limite")
  end

  it "serves documents as attachments and keeps files away from other members and organizations" do
    sign_in_as(technician)
    upload(uploaded("%PDF-1.4\n%laudo", "laudo.pdf", "application/pdf"))
    evidence = in_tenant(organization) { WorkOrderEvidence.sole }
    get work_order_evidence_path(work_order, evidence)
    expect(response.headers["Content-Disposition"]).to start_with("attachment")

    sign_in_as(create(:membership, :technician, organization:))
    get work_order_evidence_path(work_order, evidence)
    expect(response).to have_http_status(:not_found)

    other = create(:organization)
    in_tenant(other) { expect([ActiveStorage::Blob.count, ActiveStorage::Attachment.count]).to eq([0, 0]) }
  end

  it "lets the office remove evidences of open orders only" do
    sign_in_as(technician)
    upload(png_upload)
    evidence = in_tenant(organization) { WorkOrderEvidence.sole }

    delete work_order_evidence_path(work_order, evidence)
    expect(response).to have_http_status(:forbidden)

    sign_in_as(scenario[:coordinator])
    delete work_order_evidence_path(work_order, evidence)
    expect(in_tenant(organization) { [WorkOrderEvidence.count, ActiveStorage::Blob.count] }).to eq([0, 0])
  end
end
