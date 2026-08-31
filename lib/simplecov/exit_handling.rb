# frozen_string_literal: true

require "English"

#
# `at_exit` orchestration: post-suite report generation, threshold checks,
# deferral when a sibling subprocess already wrote a fresher report, and
# exit-status propagation.
#
module SimpleCov
  class << self
    # @api private
    CoverageLimits = Data.define(
      :minimum_coverage,
      :minimum_coverage_by_file,
      :minimum_coverage_by_file_overrides,
      :minimum_coverage_by_group,
      :maximum_coverage,
      :maximum_coverage_drop,
      :maximum_missed,
      :maximum_missed_per_file,
      :maximum_missed_per_file_overrides,
      :baseline
    )

    def at_exit_behavior
      # A different process than the one that called start; don't interfere.
      return unless started_in_this_process?

      # Coverage is no longer running (someone stopped it manually, or a test
      # consumed the result), so don't run exit tasks.
      return unless Coverage.running?

      # Captured BEFORE the deferral probe: its freshness check rescues
      # filesystem errors, and completing any rescue inside an at_exit handler
      # resets $ERROR_INFO to nil.
      error_exit_status = exit_status_from_exception

      # Stand down when we'd only clobber a fresher report (#581).
      return if defer_to_existing_report?

      run_exit_tasks!(error_exit_status)
    end

    # @api private -- everything the end of a measured run does, answered as the
    # exit status the process should end with rather than performed as an exit.
    # The one side effect left to the caller is ending the process, which is
    # what makes this whole path answerable from inside a test.
    def run_exit_tasks(error_exit_status = exit_status_from_exception)
      at_exit.call

      if previous_error?(error_exit_status)
        report_previous_error
        error_exit_status
      elsif ready_to_process_results?
        report_processing_failure(process_result(result))
      else
        ExitCodes::SUCCESS
      end
    end

    # @api private -- the exiting adapter over `run_exit_tasks`, called from the
    # at_exit block (which pre-captures the status, see there) and by `collate`.
    def run_exit_tasks!(error_exit_status = exit_status_from_exception)
      status = run_exit_tasks(error_exit_status)

      # Force exit with stored status (#5).
      Kernel.exit(status) unless successful?(status)
    end

    # @api private
    def exit_status_from_exception
      @exit_exception = $ERROR_INFO
      return nil unless @exit_exception

      if @exit_exception.is_a?(SystemExit)
        @exit_exception.status
      else
        ExitCodes::EXCEPTION
      end
    end

    # @api private -- strict boolean so rspec-mocks 4's predicate matcher
    # accepts it. test_unit sets status 0 on success, so SUCCESS must also be
    # treated as "not a previous error".
    def previous_error?(error_exit_status)
      return false unless error_exit_status

      !successful?(error_exit_status)
    end

    # @api private -- the notice alone; the status it accompanies is the
    # caller's to answer with.
    def report_previous_error
      return unless print_errors

      ExitCodes.print_error Color.colorize(
        "Stopped processing SimpleCov as a previous error not related to SimpleCov has been detected",
        :yellow
      )
    end

    # @api private. The process that owns final merge processing is the only one
    # that reports against thresholds, and only when its
    # `wait_for_other_processes` confirmed every sibling reported. When the wait
    # times out the merged total is partial, and comparing it against the
    # thresholds would surface a spurious violation about the missing slice.
    def ready_to_process_results?
      merge_finalization_owner? && result? &&
        (collating_result? || parallel_results_complete?)
    end

    # @api private -- answers the status it was handed, explaining it first when
    # it is a coverage failure worth explaining.
    def report_processing_failure(exit_status)
      if exit_status.positive? && print_errors
        ExitCodes.print_error Color.colorize(
          "SimpleCov failed with exit #{exit_status} due to a coverage related error", :red
        )
      end
      exit_status
    end

    # @api private. The history entry is recorded on the same successful-run
    # condition `.last_run.json` uses, so a run that failed its thresholds
    # becomes neither the drop baseline nor a data point in the trend.
    def process_result(result)
      result_exit_status = result_exit_status(result)
      if successful?(result_exit_status)
        write_last_run(result)
        History.record(result)
      end
      result_exit_status
    end

    # mutant:disable -- a pid is an Integer, and Integers answer ==, eql? and
    # equal? alike for the same value.
    def started_in_this_process?
      SimpleCov.pid == Process.pid
    end

    # Asked as a predicate rather than compared against `ExitCodes::SUCCESS`,
    # because two equal Integers are equal through every spelling of the
    # comparison.
    def successful?(status)
      status.zero?
    end

    def result_exit_status(result)
      ExitCodes::ExitCodeHandling.call(result, coverage_limits: build_coverage_limits)
    end

  private

    # Every CoverageLimits member is named after the configuration reader that
    # supplies it, so a new limit only has to be added to the Data definition
    # and the checks.
    def build_coverage_limits
      limits = CoverageLimits.members.to_h { |name| [name, public_send(name)] } #: Hash[Symbol, untyped]
      CoverageLimits.new(**limits)
    end
  end
end
