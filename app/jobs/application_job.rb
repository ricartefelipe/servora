# frozen_string_literal: true

# Jobs receive identifiers only and rebuild their context (organization,
# records) from the database under RLS. Transient errors are retried a bounded
# number of times; permanent errors are discarded and logged.
class ApplicationJob < ActiveJob::Base
  retry_on Servora::TransientError, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout,
    wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError, Servora::PermanentError do |job, error|
    Rails.logger.error(event: "job.discarded", job: job.class.name, job_id: job.job_id, error_class: error.class.name)
  end

  around_perform do |job, block|
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    outcome = "failed"
    Current.set(request_id: job.job_id) { block.call }
    outcome = "succeeded"
  ensure
    Servora::Metrics.increment(:jobs_total, { job: job.class.name, outcome: })
    Servora::Metrics.observe(:job_duration_seconds, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
      { job: job.class.name })
  end
end
