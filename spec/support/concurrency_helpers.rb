# frozen_string_literal: true

# Runs blocks in parallel threads, each with its own database connection.
# A barrier releases all threads at once so they really compete; there are no
# sleeps: ordering is decided by PostgreSQL locks and constraints.
module ConcurrencyHelpers
  module_function

  def run_in_parallel(count, &block)
    barrier = Concurrent::CyclicBarrier.new(count)
    threads = Array.new(count) do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.wait(10)
          block.arity.zero? ? yield : yield(index)
        end
      end
    end
    threads.map { |thread| thread.join(30)&.value }
  end

  # Blocks until a backend other than the current one is waiting on a lock.
  # Polls pg_stat_activity (state change, not elapsed time) with a deadline.
  def wait_for_lock_wait(timeout: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      loop do
        waiting = connection.select_value(<<~SQL.squish)
          SELECT count(*) FROM pg_stat_activity
          WHERE wait_event_type = 'Lock' AND datname = current_database() AND pid <> pg_backend_pid()
        SQL
        return true if waiting.to_i.positive?
        raise "no backend started waiting for a lock" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        Thread.pass
      end
    end
  end
end
