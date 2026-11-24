# frozen_string_literal: true

module Api
  module V1
    # Public API (JSON). Authentication: "Authorization: Bearer <token>". The
    # token digest resolves the organization (SECURITY DEFINER, tenant id
    # only); the credential is then loaded under RLS and checked on every
    # request (not revoked, not expired, scope granted).
    class BaseController < ActionController::API
      MAX_PER_PAGE = 100
      DEFAULT_PER_PAGE = 25

      rate_limit to: 300, within: 1.minute, by: -> { request.authorization.to_s.last(16) },
        with: lambda {
          render_error(:too_many_requests, "rate_limited", "Limite de requisições atingido. Tente novamente em instantes.")
        }

      around_action :within_credential

      rescue_from ActiveRecord::RecordNotFound do
        render_error(:not_found, "not_found", "Recurso não encontrado.")
      end
      rescue_from ActionController::ParameterMissing, ArgumentError do |error|
        render_error(:bad_request, "bad_request", error.message)
      end
      rescue_from Servora::RuleViolation, ActiveRecord::RecordInvalid do |error|
        render_error(:unprocessable_content, "rule_violation", error.message)
      end

      private

      attr_reader :current_credential

      def within_credential(&)
        token = request.authorization.to_s[/\ABearer (\S+)\z/, 1]
        organization_id = ApiCredential.organization_for(token)
        return render_error(:unauthorized, "unauthorized", "Credencial inválida, revogada ou expirada.") unless organization_id

        Servora::Tenancy.with_organization(organization_id) do
          @current_credential = ApiCredential.includes(created_by: :user).find_by!(token_digest: ApiCredential.digest(token))
          touch_usage
          Current.set(api_credential: @current_credential, organization: Organization.find(organization_id), &)
        end
      end

      def touch_usage
        return if current_credential.last_used_at&.after?(5.minutes.ago)

        current_credential.update_column(:last_used_at, Time.current) # rubocop:disable Rails/SkipsModelValidations -- usage timestamp
      end

      def require_scope!(scope)
        return if current_credential.allows?(scope)

        render_error(:forbidden, "insufficient_scope", "A credencial não tem o escopo #{scope}.")
      end

      def paginate(scope)
        per_page = params.dig(:page, :size).to_i.clamp(1, MAX_PER_PAGE)
        per_page = DEFAULT_PER_PAGE if params.dig(:page, :size).blank?
        pagination = Pagination.new(scope, page: params.dig(:page, :number) || 1, per_page:)
        { records: pagination.records,
          meta: { page: pagination.page, per_page: pagination.per_page,
                  next_page: pagination.next_page? ? pagination.page + 1 : nil } }
      end

      def updated_since(scope)
        value = params[:updated_since]
        return scope if value.blank?

        scope.where(updated_at: Time.iso8601(value)..)
      rescue ArgumentError
        raise ArgumentError, "updated_since deve estar no formato ISO 8601"
      end

      def render_page(scope, &)
        page = paginate(scope)
        render json: { data: page[:records].map(&), meta: page[:meta] }
      end

      def render_error(status, code, message)
        render json: { error: { code:, message: } }, status:
      end
    end
  end
end
