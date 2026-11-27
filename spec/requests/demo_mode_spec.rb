# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Demo mode" do
  def notice
    response.parsed_body.at_css("section[aria-labelledby='demo-access-title']")
  end

  def profile_buttons
    notice.css("button[type=button][data-action='demo-login#fill']")
  end

  describe "sign-in page" do
    context "when SERVORA_DEMO is not 1", demo_mode: false do
      it "does not show the demonstration notice nor any demonstration account" do
        get "/"

        expect(response).to have_http_status(:ok)
        expect(notice).to be_nil
        expect(response.body).not_to include("Ambiente de demonstração", Servora::Demo.password, "/caixa-de-entrada",
          "demo-login", *Servora::Demo.accounts.map(&:email))
      end

      it "keeps password recovery, sign-up, confirmation and unlock" do
        get "/"

        expect(response.body).to include("Esqueceu a senha?", "Criar conta", "Reenviar confirmação de e-mail",
          "Desbloquear conta")
      end

      it "requires exactly the value 1" do
        %w[true yes on 0].each do |value|
          with_environment("SERVORA_DEMO" => value) { get "/" }

          expect(notice).to be_nil, "SERVORA_DEMO=#{value} must not enable demo mode"
        end
      end
    end

    context "when SERVORA_DEMO=1", :demo_mode do
      it "shows the notice with the shared password above the sign-in form" do
        get "/"

        expect(response).to have_http_status(:ok)
        expect(notice.at_css("h2").text.squish).to eq("Ambiente de demonstração")
        expect(notice.at_css("code").text).to eq(ENV.fetch("SEED_PASSWORD", "servora-demo-2026"))
        expect(notice.text).to include("Os dados voltam ao estado inicial todos os dias.")
        expect(response.body.index('id="demo-access-title"')).to be < response.body.index(%(action="#{user_session_path}"))
      end

      it "offers one button per demonstration profile, readable without JavaScript" do
        get "/"

        emails = %w[
          ana@clima-norte.test bruno@clima-norte.test carla@clima-norte.test diego@clima-norte.test
          gabriela@clima-norte.test heitor@clima-norte.test
        ]
        labels = [
          "Proprietária ana@clima-norte.test", "Coordenador bruno@clima-norte.test", "Atendente carla@clima-norte.test",
          "Técnico abre a agenda de campo diego@clima-norte.test", "Financeiro gabriela@clima-norte.test",
          "Auditor abre a trilha de auditoria heitor@clima-norte.test"
        ]
        expect(profile_buttons.pluck("data-demo-login-email-param")).to eq(emails)
        expect(profile_buttons.map { |button| button.text.squish }).to eq(labels)
        expect(notice.to_h).to include("data-controller" => "demo-login", "data-demo-login-email-field-value" => "user_email",
          "data-demo-login-password-field-value" => "user_password")
      end

      it "links to the demonstration inbox in a new tab, outside Turbo" do
        with_environment("SERVORA_DEMO_INBOX_URL" => nil) { get "/" }

        inbox = notice.at_css("a[href='/caixa-de-entrada']")
        expect(inbox.text.squish).to eq("Caixa de entrada da demonstração (abre em nova aba)")
        expect(inbox.to_h).to include("target" => "_blank", "rel" => "noopener", "data-turbo" => "false")
      end

      it "never cuts an e-mail address, which wraps below the profile on narrow screens" do
        get "/"

        emails = profile_buttons.map { |button| button.at_css("span.font-mono") }
        expect(emails.map(&:text)).to eq(Servora::Demo.accounts.map(&:email))
        expect(emails.map { |email| email["class"].split }).to all(include("whitespace-nowrap"))
        expect(emails.flat_map { |email| email["class"].split }).not_to include("truncate")
        expect(profile_buttons.map { |button| button["class"].split }).to all(include("flex-wrap"))
      end

      it "offers no inbox link when the instance has no demonstration inbox" do
        with_environment("SERVORA_DEMO_INBOX_URL" => "") { get "/" }

        expect(response).to have_http_status(:ok)
        expect(notice.css("a")).to be_empty
        expect(notice.text).not_to include("Caixa de entrada")
        expect(notice.text).to include("Os dados voltam ao estado inicial todos os dias.")
      end

      it "leaves out password recovery, sign-up, confirmation and unlock, which do not apply to shared accounts" do
        get "/"

        expect(response.body).not_to include("Esqueceu a senha?", "Criar conta", "Reenviar confirmação", "Desbloquear conta")
        [new_user_password_path, new_user_registration_path, new_user_confirmation_path, new_user_unlock_path].each do |path|
          expect(response.parsed_body.at_css("a[href='#{path}']")).to be_nil, path
        end
      end

      it "shows the password configured for the seeds" do
        with_environment("SEED_PASSWORD" => "senha-publica-da-demo") { get "/" }

        expect(notice.at_css("code").text).to eq("senha-publica-da-demo")
        expect(notice["data-demo-login-password-value"]).to eq("senha-publica-da-demo")
      end

      it "exposes no other secret" do
        get "/"

        secrets = [
          Rails.application.secret_key_base, ENV.fetch("DB_APP_PASSWORD", nil), ENV.fetch("DB_OWNER_PASSWORD", nil),
          ENV.fetch("METRICS_TOKEN", nil), ENV.fetch("PLATFORM_ASAAS_API_KEY", nil)
        ].compact_blank
        expect(secrets).not_to be_empty
        secrets.each { |secret| expect(response.body).not_to include(secret) }
      end

      it "keeps to the strict content security policy" do
        get "/"

        attributes = notice.css("*").flat_map { |node| node.attribute_nodes.map(&:name) }
        expect(notice.css("script, style")).to be_empty
        expect(attributes.grep(/\A(style|on\w+)\z/)).to be_empty
        expect(response.headers["Content-Security-Policy"]).to include("script-src 'self'", "style-src 'self'")
      end
    end
  end

  describe "multi-factor enrollment for privileged roles" do
    let(:organization) { create(:organization, mfa_required_for_privileged: true) }
    let(:owner) { create(:membership, :owner, organization:) }
    let(:reminder) { "Seu perfil exige verificação em duas etapas" }

    context "when SERVORA_DEMO is not 1", demo_mode: false do
      it "reminds privileged members during the grace period" do
        sign_in_as(owner)

        get dashboard_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(reminder)
      end

      it "blocks privileged members after the deadline" do
        in_tenant(organization) { owner.update!(created_at: 10.days.ago) }
        sign_in_as(owner)

        get dashboard_path

        expect(response).to redirect_to(new_account_two_factor_path)
      end
    end

    context "when SERVORA_DEMO=1", :demo_mode do
      it "shows no reminder to privileged members" do
        sign_in_as(owner)

        get dashboard_path

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(reminder)
      end

      it "does not block privileged members after the deadline" do
        in_tenant(organization) { owner.update!(created_at: 10.days.ago) }
        sign_in_as(owner)

        get dashboard_path

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(reminder)
      end
    end
  end
end
