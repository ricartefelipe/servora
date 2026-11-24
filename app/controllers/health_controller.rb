# frozen_string_literal: true

# Liveness and readiness probes.
#
# * GET /up    - liveness: the process is running and can serve HTTP. It does not
#                touch dependencies, so a database outage does not restart pods.
# * GET /ready - readiness: every database the process needs answers and there
#                are no pending migrations. Returns 503 otherwise, so the load
#                balancer stops routing traffic without killing the process.
class HealthController < ActionController::API
  READINESS_TIMEOUT_MS = 2_000

  def live
    render json: { status: "ok" }
  end

  def ready
    checks = Servora::ReadinessCheck.new(timeout_ms: READINESS_TIMEOUT_MS).call
    status = checks.values.all? { |check| check[:ok] } ? :ok : :service_unavailable
    render json: { status: status == :ok ? "ready" : "unavailable", checks: checks }, status:
  end
end
