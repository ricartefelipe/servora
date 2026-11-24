# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Organization context per request" do
  let(:organization_a) { create(:organization, name: "Organização A") }
  let(:organization_b) { create(:organization, name: "Organização B") }
  let(:membership) { create(:membership, :admin, organization: organization_a) }

  it "asks for an organization before opening tenant pages" do
    sign_in membership.user

    get dashboard_path

    expect(response).to redirect_to(organizations_path)
  end

  it "does not accept an organization the user does not belong to" do
    sign_in_as(membership)

    post select_organization_path(organization_b.id)

    expect(response).to have_http_status(:not_found)
    get dashboard_path
    expect(response.body).to include("Organização A")
    expect(response.body).not_to include("Organização B")
  end

  it "denies access on the next request after the membership is deactivated" do
    sign_in_as(membership)
    in_tenant(organization_a) { membership.update!(status: "deactivated") }

    get dashboard_path

    expect(response).to redirect_to(organizations_path)
    expect(flash[:alert]).to include("não está disponível")
  end

  it "switches organizations only through a validated membership" do
    create(:membership, :technician, organization: organization_b, user: membership.user)
    sign_in_as(membership)

    post select_organization_path(organization_b.id)
    get dashboard_path

    expect(response.body).to include("Organização B")
  end

  it "answers 404 for records of another organization" do
    foreign = create(:membership, organization: organization_b)
    sign_in_as(membership)

    get edit_member_path(foreign)

    expect(response).to have_http_status(:not_found)
  end

  it "blocks privileged members without MFA after the grace period" do
    in_tenant(organization_a) { organization_a.update!(mfa_required_for_privileged: true) }
    in_tenant(organization_a) { membership.update!(created_at: 10.days.ago) }
    sign_in_as(membership)

    get dashboard_path

    expect(response).to redirect_to(new_account_two_factor_path)
  end
end
