# frozen_string_literal: true

require "English"

# `at_exit` orchestration: post-suite report generation, threshold
# checks, deferral when a sibling subprocess already wrote a fresher
# report, and exit-status propagation.
module SimpleCov
  class << self
    # @api private
    CoverageLimits = Struct.new(
      :minimum_coverage,
      :minimum_coverage_by_file,
      :minimum_coverage_by_file_overrides,
      :minimum_coverage_by_group,
      :maximum_coverage,
      :maximum_coverage_drop,
      keyword_init: true
    )

    def at_exit_behavior
      # If we are in a different process than called start, don't interfere.
      return if SimpleCov.pid != Process.pid

      # If Coverage is no longer running (e.g. someone manually stopped it
      # or a test consumed the result) then don't run exit tasks.
      return unless Coverage.running?

      # Stand down when we'd only clobber a fresher report. See
      # `defer_to_existing_report?` and issue #581.
      return if defer_to_existing_report?

      SimpleCov.run_exit_tasks!
    end

    # Returns true when our process has no coverage data to contribute
    # (after the resultset merge) and a newer report already exists on
    # disk. Typically fires when `SimpleCov.start` ran in a parent
    # process — e.g. a Rakefile or Rails' `Bundler.require` — that
    # shelled out to the test runner. See issue #581.
    def defer_to_existing_report?
      return false unless existing_report_newer_than_us?

      res = result
      empty = res.nil? || res.files.empty?
      warn_about_deferred_report if empty
      empty
    end

    def existing_report_newer_than_us?
      return false unless process_start_time

      last_run_path = File.join(coverage_path, ".last_run.json")
      File.exist?(last_run_path) && File.mtime(last_run_path) > process_start_time
    end

    def warn_about_deferred_report
      return unless print_errors

      warn SimpleCov::Color.colorize(
        "Skipping SimpleCov report — this process tracked no application code and a newer " \
        "report already exists at #{coverage_path}. This usually means SimpleCov.start ran in a " \
        "parent process (e.g. a Rakefile or Rails' Bundler.require) that shelled out to the test " \
        "runner. See https://github.com/simplecov-ruby/simplecov/issues/581.",
        :yellow
      )
    end

    # @api private — called from the at_exit block.
    def run_exit_tasks!
      error_exit_status = exit_status_from_exception

      at_exit.call

      exit_and_report_previous_error(error_exit_status) if previous_error?(error_exit_status)
      process_results_and_report_error if ready_to_process_results?
    end

    # @api private — returns the exit status from the exit exception.
    def exit_status_from_exception
      @exit_exception = $ERROR_INFO
      return nil unless @exit_exception

      if @exit_exception.is_a?(SystemExit)
        @exit_exception.status
      else
        SimpleCov::ExitCodes::EXCEPTION
      end
    end

    # @api private — strict boolean so rspec-mocks 4's predicate matcher
    # accepts it. test_unit sets status 0 on success, so SUCCESS must
    # also be treated as "not a previous error".
    def previous_error?(error_exit_status)
      !!(error_exit_status && error_exit_status != SimpleCov::ExitCodes::SUCCESS)
    end

    # @api private
    def exit_and_report_previous_error(exit_status)
      if print_errors
        warn SimpleCov::Color.colorize(
          "Stopped processing SimpleCov as a previous error not related to SimpleCov has been detected",
          :yellow
        )
      end
      Kernel.exit(exit_status)
    end

    # @api private — the first worker in a parallel run is the only
    # one that reports against thresholds, and only when its
    # `wait_for_other_processes` confirmed every sibling reported.
    # When the wait times out, the merged total is partial and
    # comparing it against `minimum_coverage` / `maximum_coverage`
    # would surface a spurious "below minimum" violation about the
    # missing slice rather than a real shortfall.
    def ready_to_process_results?
      final_result_process? && result? && parallel_results_complete?
    end

    def process_results_and_report_error
      exit_status = process_result(result)

      # Force exit with stored status (see github issue #5)
      return unless exit_status.positive?

      if print_errors
        warn SimpleCov::Color.colorize(
          "SimpleCov failed with exit #{exit_status} due to a coverage related error", :red
        )
      end
      Kernel.exit exit_status
    end

    # @api private — `exit_status = SimpleCov.process_result(SimpleCov.result)`.
    def process_result(result)
      result_exit_status = result_exit_status(result)
      write_last_run(result) if result_exit_status == SimpleCov::ExitCodes::SUCCESS
      result_exit_status
    end

    def result_exit_status(result)
      ExitCodes::ExitCodeHandling.call(result, coverage_limits: build_coverage_limits)
    end

  private

    def build_coverage_limits
      CoverageLimits.new(
        minimum_coverage: minimum_coverage,
        minimum_coverage_by_file: minimum_coverage_by_file,
        minimum_coverage_by_file_overrides: minimum_coverage_by_file_overrides,
        minimum_coverage_by_group: minimum_coverage_by_group,
        maximum_coverage: maximum_coverage,
        maximum_coverage_drop: maximum_coverage_drop
      )
    end
  end
end
