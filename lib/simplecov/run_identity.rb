# frozen_string_literal: true

require "securerandom"

module SimpleCov
  # Identifies one test invocation and each top-level parallel worker within
  # it. Forked subprocesses inherit both values from their parent worker.
  module RunIdentity
  module_function

    # Returns the run id together with its provenance: `true` when the id
    # alone proves same-run membership (explicitly configured, derived from
    # parallel_tests' per-invocation pid file, or freshly random), `false`
    # when it was inferred from the parent pid, which consecutive runs
    # launched by the same long-lived parent process share.
    def generate
      explicit = ENV.fetch("SIMPLECOV_RUN_ID", nil)
      return [explicit, true] if explicit && !explicit.empty?

      pid_file = ENV.fetch("PARALLEL_PID_FILE", nil)
      return ["parallel-tests:#{File.basename(pid_file)}", true] if pid_file && !pid_file.empty?

      return ["parallel-parent:#{Process.ppid}", false] if SimpleCov::ParallelAdapters.current

      [SecureRandom.uuid, true]
    end

    def worker_id
      explicit = ENV.fetch("SIMPLECOV_WORKER_ID", nil)
      return explicit if explicit && !explicit.empty?

      number = ENV.fetch("TEST_ENV_NUMBER", nil)
      return number.empty? ? "1" : number if number

      Process.pid.to_s
    end

    # Whether the current run id alone proves same-run membership. Decided
    # where the id is generated, never re-inferred from the id's shape, so
    # an explicit SIMPLECOV_RUN_ID that happens to look like an inferred
    # one is still trusted.
    def authoritative?
      materialize_current
      @authoritative
    end

    def current
      materialize_current
      @current
    end

    def materialize_current
      @current, @authoritative = generate unless defined?(@current)
    end

    def current_worker_id
      @current_worker_id ||= worker_id
    end

    def prepare
      SimpleCov::ParallelAdapters.current
      SimpleCov.run_id
      SimpleCov.worker_id
    end

    # Mixed into SimpleCov after ParallelAdapters has loaded.
    module Accessors
      def run_id
        SimpleCov::RunIdentity.current
      end

      def worker_id
        SimpleCov::RunIdentity.current_worker_id
      end
    end
  end
end
