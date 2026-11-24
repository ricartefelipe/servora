# frozen_string_literal: true

require "net/protocol"

module Outbox
  # Decides whether a failed attempt should be retried.
  module FailureClassifier
    TRANSIENT = [
      Servora::TransientError,
      ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::QueryCanceled,
      ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError,
      ActiveJob::EnqueueError,
      Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, Timeout::Error
    ].freeze

    PERMANENT = [
      Servora::PermanentError, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid,
      ArgumentError, KeyError, NameError, NoMethodError
    ].freeze

    module_function

    # Unknown errors are retried until max_attempts is reached.
    def transient?(error)
      return true if TRANSIENT.any? { |klass| error.is_a?(klass) }
      return false if PERMANENT.any? { |klass| error.is_a?(klass) }

      true
    end
  end
end
