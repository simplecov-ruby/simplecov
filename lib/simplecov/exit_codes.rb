# frozen_string_literal: true

module SimpleCov
  # Exit statuses SimpleCov sets when coverage checks fail, and the output
  # helper the enforcement machinery reports through.
  module ExitCodes
    SUCCESS = 0
    EXCEPTION = 1
    MINIMUM_COVERAGE = 2
    MAXIMUM_COVERAGE_DROP = 3
    MAXIMUM_COVERAGE = 4

    # Threshold-violation reports and exit-status notices are the output of
    # the enforcement feature, not Ruby warnings: routing them through
    # `Kernel#warn` made `-W0` swallow the explanation for a failing exit
    # code, let `Warning.warn` hooks (warning trackers, raise-on-warning
    # test setups) intercept them mid-`at_exit`, and fed colorized text to
    # warning logs. `print_errors false` remains the intended opt-out.
    def self.print_error(message)
      $stderr.puts message # rubocop:disable Style/StderrPuts
    end
  end
end

require_relative "exit_codes/exit_code_handling"
require_relative "exit_codes/maximum_coverage_drop_check"
require_relative "exit_codes/maximum_overall_coverage_check"
require_relative "exit_codes/minimum_coverage_by_file_check"
require_relative "exit_codes/minimum_coverage_by_group_check"
require_relative "exit_codes/minimum_overall_coverage_check"
