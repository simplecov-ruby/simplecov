# frozen_string_literal: true

require "English"

#
# Code coverage for ruby. Please check out README for a full introduction.
#
module SimpleCov
  # Raised when a user's configuration is internally inconsistent — e.g.
  # every coverage criterion has been disabled.
  class ConfigurationError < StandardError; end

  class << self
    CRITERION_TO_RUBY_COVERAGE = {
      branch: :branches,
      line: :lines,
      method: :methods,
      oneshot_line: :oneshot_lines
    }.freeze

    # `:oneshot_line` data is folded into the `:line` bucket of
    # `coverage_statistics` by `ResultAdapter`, so use `:line` to look
    # up stats for either criterion.
    def coverage_statistics_key(criterion)
      criterion == :oneshot_line ? :line : criterion
    end

    attr_accessor :pid

    # When this process started tracking coverage. Captured by SimpleCov.start
    # so JSONFormatter can detect when an existing coverage.json was written
    # by a sibling process running concurrently.
    attr_accessor :process_start_time

    # Basically, should we take care of at_exit behavior or something else?
    # Used by the minitest plugin. See lib/minitest/simplecov_plugin.rb
    attr_accessor :external_at_exit

    # Coerce to a proper boolean so rspec-mocks 4's predicate matcher
    # (`expect(...).not_to be_external_at_exit`) accepts the result — a
    # bare attr reader returns the raw value (nil, false, or truthy),
    # but the matcher now requires strict `true` / `false`.
    def external_at_exit?
      !!@external_at_exit
    end

    #
    # Sets up SimpleCov to run against your project.
    # You can optionally specify a profile to use as well as configuration with a block:
    #   SimpleCov.start
    #    OR
    #   SimpleCov.start 'rails' # using rails profile
    #    OR
    #   SimpleCov.start do
    #     add_filter 'test'
    #   end
    #     OR
    #   SimpleCov.start 'rails' do
    #     add_filter 'test'
    #   end
    #
    # Please check out the RDoc for SimpleCov::Configuration to find about available config options
    #
    def start(profile = nil, &)
      initial_setup(profile, &)
      start_tracking
      install_at_exit_hook
    end

    #
    # Install the at_exit hook that formats results and runs exit-code
    # checks. `SimpleCov.start` calls this automatically. Idempotent —
    # safe to call multiple times. Callers that drive the formatting
    # pipeline themselves (e.g., dogfood test setups) can skip it by
    # using `start_tracking` directly instead of `start`.
    #
    def install_at_exit_hook
      return if @at_exit_hook_installed

      @at_exit_hook_installed = true
      defer_to_minitest_after_run if minitest_autorun_pending?
      Kernel.at_exit do
        next if SimpleCov.external_at_exit?

        SimpleCov.at_exit_behavior
      end
    end

    #
    # Begin coverage tracking without applying configuration. Pairs with
    # `SimpleCov.configure { ... }` for callers that want to separate
    # the two — for example a dogfood test that has already started
    # `Coverage` itself before requiring simplecov, but still wants the
    # process_start_time / pid / fork-hook bookkeeping.
    #
    def start_tracking
      require "coverage"
      warn_if_jruby_full_trace_disabled
      validate_coverage_criteria!
      # simplecov:disable — fork-hook is enabled via SimpleCov.enable_for_subprocesses, off by default
      require_relative "simplecov/process" if SimpleCov.enabled_for_subprocesses? &&
                                              ::Process.respond_to?(:_fork)
      # simplecov:enable

      make_parallel_tests_available

      @result = nil
      self.pid = Process.pid
      self.process_start_time = Time.now

      start_coverage_measurement
    end

    #
    # Collate a series of SimpleCov result files into a single SimpleCov output.
    #
    # You can optionally specify configuration with a block:
    #   SimpleCov.collate Dir["simplecov-resultset-*/.resultset.json"]
    #    OR
    #   SimpleCov.collate Dir["simplecov-resultset-*/.resultset.json"], 'rails' # using rails profile
    #    OR
    #   SimpleCov.collate Dir["simplecov-resultset-*/.resultset.json"] do
    #     add_filter 'test'
    #   end
    #    OR
    #   SimpleCov.collate Dir["simplecov-resultset-*/.resultset.json"], 'rails' do
    #     add_filter 'test'
    #   end
    #
    # Please check out the RDoc for SimpleCov::Configuration to find about
    # available config options, or checkout the README for more in-depth
    # information about coverage collation
    #
    # By default `collate` ignores the merge_timeout so all results of all files specified will be
    # merged together. If you want to honor the merge_timeout then provide the keyword argument
    # `ignore_timeout: false`.
    #
    def collate(result_filenames, profile = nil, ignore_timeout: true, &block)
      raise ArgumentError, "There are no reports to be merged" if result_filenames.empty?

      initial_setup(profile, &block)

      # Use the ResultMerger to produce a single, merged result, ready to use.
      @result = ResultMerger.merge_and_store(*result_filenames, ignore_timeout: ignore_timeout)

      run_exit_tasks!
    end

    #
    # Returns the result for the current coverage run, merging it across test suites
    # from cache using SimpleCov::ResultMerger if use_merging is activated (default)
    #
    def result
      return @result if result?

      # Collect our coverage result
      process_coverage_result if defined?(Coverage) && Coverage.running?

      # If we're using merging of results, store the current result
      # first (if there is one), then merge the results and return those
      if use_merging
        wait_for_other_processes
        SimpleCov::ResultMerger.store_result(@result) if result?
        @result = SimpleCov::ResultMerger.merged_result
      end

      @result
    end

    #
    # Returns nil if the result has not been computed
    # Otherwise, returns the result
    #
    def result?
      defined?(@result) && @result
    end

    #
    # Applies the configured filters to the given array of SimpleCov::SourceFile items
    #
    def filtered(files)
      result = files.clone
      filters.each do |filter|
        result = result.reject { |source_file| filter.matches?(source_file) }
      end
      SimpleCov::FileList.new result
    end

    #
    # Applies the configured groups to the given array of SimpleCov::SourceFile items
    #
    def grouped(files)
      return {} if groups.empty?

      grouped = groups.transform_values do |filter|
        SimpleCov::FileList.new(files.select { |source_file| filter.matches?(source_file) })
      end

      in_group  = grouped.values.flat_map(&:to_a)
      ungrouped = files.reject { |source_file| in_group.include?(source_file) }
      grouped["Ungrouped"] = SimpleCov::FileList.new(ungrouped) if ungrouped.any?

      grouped
    end

    #
    # Applies the profile of given name on SimpleCov configuration
    #
    def load_profile(name)
      profiles.load(name)
    end

    #
    # Clear out the previously cached .result. Primarily useful in testing
    #
    def clear_result
      @result = nil
    end

    def at_exit_behavior
      # If we are in a different process than called start, don't interfere.
      return if SimpleCov.pid != Process.pid

      # If Coverage is no longer running (e.g. someone manually stopped it
      # or a test consumed the result) then don't run exit tasks.
      SimpleCov.run_exit_tasks! if Coverage.running?
    end

    # @api private
    #
    # Called from at_exit block
    #
    def run_exit_tasks!
      error_exit_status = exit_status_from_exception

      at_exit.call

      exit_and_report_previous_error(error_exit_status) if previous_error?(error_exit_status)
      process_results_and_report_error if ready_to_process_results?
    end

    #
    # @api private
    #
    # Returns the exit status from the exit exception
    #
    def exit_status_from_exception
      # Capture the current exception if it exists
      @exit_exception = $ERROR_INFO
      return nil unless @exit_exception

      if @exit_exception.is_a?(SystemExit)
        @exit_exception.status
      else
        SimpleCov::ExitCodes::EXCEPTION
      end
    end

    # @api private
    #
    # Returns a real boolean (rather than a truthy nil / Integer), so
    # rspec-mocks 4's predicate matcher accepts it. Normally a non-nil
    # exit status would be enough, but test_unit sets status 0 on
    # success, so SUCCESS must also be treated as "not a previous error".
    def previous_error?(error_exit_status)
      !!(error_exit_status && error_exit_status != SimpleCov::ExitCodes::SUCCESS)
    end

    #
    # @api private
    #
    # Thinking: Move this behavior earlier so if there was an error we do nothing?
    def exit_and_report_previous_error(exit_status)
      if print_error_status
        warn SimpleCov::Color.colorize(
          "Stopped processing SimpleCov as a previous error not related to SimpleCov has been detected",
          :yellow
        )
      end
      Kernel.exit(exit_status)
    end

    # @api private
    def ready_to_process_results?
      final_result_process? && result?
    end

    def process_results_and_report_error
      exit_status = process_result(result)

      # Force exit with stored status (see github issue #5)
      return unless exit_status.positive?

      if print_error_status
        warn SimpleCov::Color.colorize(
          "SimpleCov failed with exit #{exit_status} due to a coverage related error", :red
        )
      end
      Kernel.exit exit_status
    end

    # @api private
    #
    # Usage:
    #   exit_status = SimpleCov.process_result(SimpleCov.result, exit_status)
    #
    def process_result(result)
      result_exit_status = result_exit_status(result)
      write_last_run(result) if result_exit_status == SimpleCov::ExitCodes::SUCCESS
      result_exit_status
    end

    # @api private
    CoverageLimits = Struct.new(
      :minimum_coverage,
      :minimum_coverage_by_file,
      :minimum_coverage_by_group,
      :maximum_coverage_drop,
      keyword_init: true
    )
    def result_exit_status(result)
      coverage_limits = CoverageLimits.new(
        minimum_coverage: minimum_coverage, minimum_coverage_by_file: minimum_coverage_by_file,
        minimum_coverage_by_group: minimum_coverage_by_group, maximum_coverage_drop: maximum_coverage_drop
      )

      ExitCodes::ExitCodeHandling.call(result, coverage_limits: coverage_limits)
    end

    #
    # @api private
    #
    def final_result_process?
      return true unless defined?(ParallelTests) && ENV["TEST_ENV_NUMBER"]

      # parallel_tests sets the first process's TEST_ENV_NUMBER to "" and
      # `ParallelTests.last_process?` does `"" == "1"`, which is false —
      # so with PARALLEL_TEST_GROUPS=1 the only process in the run never
      # runs the final-result work. Treat any single-group run as final.
      ENV["PARALLEL_TEST_GROUPS"].to_i <= 1 || ParallelTests.last_process?
    end

    #
    # @api private
    #
    # simplecov:disable
    # Methods below only fire under parallel_tests; not reachable from a
    # single-process rspec run. Cucumber's test_projects exercise the
    # parallel_tests integration end-to-end in subprocesses, but those
    # subprocesses don't merge their Coverage data back into the parent
    # this dogfood report measures.
    def wait_for_other_processes
      return unless defined?(ParallelTests) && final_result_process?

      ParallelTests.wait_for_other_processes_to_finish

      # ParallelTests signals "done" before at_exit handlers finish, so other
      # processes may still be writing their results. Poll the resultset until
      # all parallel groups have reported or a timeout is reached.
      wait_for_parallel_results
    end
    # simplecov:enable

    # @api private
    def wait_for_parallel_results
      expected = ENV["PARALLEL_TEST_GROUPS"]&.to_i
      return unless expected && expected > 1 # simplecov:disable branch — only false in real parallel_tests run

      # simplecov:disable — only fires when ENV is set with >1 group
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      loop do
        resultset = SimpleCov::ResultMerger.read_resultset
        break if resultset.size >= expected
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.1
      end
      # simplecov:enable
    end

    #
    # @api private
    #
    def write_last_run(result)
      SimpleCov::LastRun.write(result:
        result.coverage_statistics.transform_values do |stats|
          round_coverage(stats.percent)
        end)
    end

    #
    # @api private
    #
    # Rounding down to be extra strict, see #679
    def round_coverage(coverage)
      coverage.floor(2)
    end

  private

    def initial_setup(profile, &block)
      load_profile(profile) if profile
      configure(&block) if block
    end

    #
    # Trigger Coverage.start with the configured criteria. Every supported
    # runtime (CRuby >= 3.1, JRuby >= 9.4, TruffleRuby >= 22) accepts the
    # criteria-hash form, so no compatibility fallback is needed.
    #
    def start_coverage_measurement
      start_coverage_with_criteria
    end

    def start_coverage_with_criteria
      start_arguments = coverage_criteria.to_h do |criterion|
        [lookup_corresponding_ruby_coverage_name(criterion), true]
      end

      start_arguments[:eval] = true if coverage_for_eval_enabled?

      Coverage.start(start_arguments) unless Coverage.running?
    end

    def lookup_corresponding_ruby_coverage_name(criterion)
      CRITERION_TO_RUBY_COVERAGE.fetch(criterion)
    end

    #
    # Finds files that were to be tracked but were not loaded and initializes
    # the line-by-line coverage to zero (if relevant) or nil (comments / whitespace etc).
    #
    def add_not_loaded_files(result)
      return [result, Set.new] unless tracked_files

      result = result.dup
      # Glob and expand relative to SimpleCov.root, not Dir.pwd — test runners
      # that chdir (or CI scripts that invoke the suite from a subdir) would
      # otherwise silently miss the unloaded-file injection and produce a
      # different file set per environment. See issue #1106.
      not_loaded_files = Dir.glob(tracked_files, base: root).each_with_object(Set.new) do |file, set|
        absolute_path = File.expand_path(file, root)
        next if result.key?(absolute_path)

        result[absolute_path] = SimulateCoverage.call(absolute_path)
        set << absolute_path
      end

      [result, not_loaded_files]
    end

    #
    # Call steps that handle process coverage result
    #
    # @return [Hash]
    #
    def process_coverage_result
      remove_useless_results
      adapt_coverage_result
      result_with_not_loaded_files
    end

    #
    # Unite the result so it wouldn't matter what coverage type was called
    #
    # @return [Hash]
    #
    def adapt_coverage_result
      @result = SimpleCov::ResultAdapter.call(@result)
    end

    #
    # Filter coverage result
    # The result before filter also has result of coverage for files
    # are not related to the project like loaded gems coverage.
    #
    # @return [Hash]
    #
    def remove_useless_results
      @result = SimpleCov::UselessResultsRemover.call(Coverage.result)
    end

    #
    # Initialize result with files that are not included by coverage
    # and added inside the config block
    #
    # @return [Hash]
    #
    def result_with_not_loaded_files
      result, not_loaded_files = add_not_loaded_files(@result)
      @result = SimpleCov::Result.new(result, not_loaded_files: not_loaded_files)
    end

    # `Rake::TestTask` runs `ruby -e 'require "minitest/autorun"; ...'`,
    # which means Minitest's at_exit registers before SimpleCov's. Since
    # at_exit fires LIFO, SimpleCov's hook would otherwise run *before*
    # Minitest gets a chance to invoke the tests — and format an empty
    # resultset. When we can see that Minitest is loaded and its autorun
    # is armed, route the report through `Minitest.after_run` instead,
    # which fires after the suite completes. See issues #1099 and #1112.
    #
    # The opposite ordering (SimpleCov first, then `minitest/autorun`)
    # is handled by `lib/minitest/simplecov_plugin.rb` — Minitest's
    # plugin discovery doesn't run until `Minitest.run` starts, which
    # is too late for the SimpleCov-second case but fine for the
    # SimpleCov-first case.
    def minitest_autorun_pending?
      return false unless defined?(Minitest) && Minitest.respond_to?(:after_run)
      return false unless Minitest.class_variable_defined?(:@@installed_at_exit)

      Minitest.class_variable_get(:@@installed_at_exit)
    end

    def defer_to_minitest_after_run
      self.external_at_exit = true
      Minitest.after_run { SimpleCov.at_exit_behavior }
    end

    # parallel_tests isn't always available, see: https://github.com/grosser/parallel_tests/issues/772
    def make_parallel_tests_available
      return if defined?(ParallelTests) # simplecov:disable — only true after a previous load
      return unless probably_running_parallel_tests? # simplecov:disable — false outside parallel_tests

      # simplecov:disable — only fires under a real parallel_tests setup
      require "parallel_tests"
    rescue LoadError
      warn(
        "SimpleCov guessed you were running inside parallel tests but couldn't load it. " \
        "Please file a bug report with us!"
      )
      # simplecov:enable
    end

    def probably_running_parallel_tests?
      ENV.fetch("TEST_ENV_NUMBER", nil) && ENV.fetch("PARALLEL_TEST_GROUPS", nil)
    end

    # JRuby coverage data is unreliable unless full-trace mode is enabled.
    # @see https://github.com/jruby/jruby/issues/1196
    # @see https://github.com/simplecov-ruby/simplecov/issues/420
    # @see https://github.com/simplecov-ruby/simplecov/issues/86
    def warn_if_jruby_full_trace_disabled
      return unless defined?(JRUBY_VERSION) && defined?(JRuby) # simplecov:disable — JRuby-only branch

      # simplecov:disable — JRuby-only branches; unreachable from CRuby
      return if org.jruby.RubyInstanceConfig.FULL_TRACE_ENABLED

      warn 'Coverage may be inaccurate; set the "--debug" command line option, ' \
           'or do JRUBY_OPTS="--debug" ' \
           'or set the "debug.fullTrace=true" option in your .jrubyrc'
      # simplecov:enable
    end
  end
end

# requires are down here here for a load order reason I'm not sure what it is about
require "set"
require "forwardable"
require_relative "simplecov/color"
require_relative "simplecov/configuration"
SimpleCov.extend SimpleCov::Configuration
require_relative "simplecov/coverage_statistics"
require_relative "simplecov/coverage_violations"
require_relative "simplecov/exit_codes"
require_relative "simplecov/profiles"
require_relative "simplecov/source_file/line"
require_relative "simplecov/source_file/branch"
require_relative "simplecov/source_file/method"
require_relative "simplecov/source_file"
require_relative "simplecov/file_list"
require_relative "simplecov/result"
require_relative "simplecov/filter"
require_relative "simplecov/formatter"
require_relative "simplecov/last_run"
require_relative "simplecov/lines_classifier"
require_relative "simplecov/result_merger"
require_relative "simplecov/command_guesser"
require_relative "simplecov/version"
require_relative "simplecov/result_adapter"
require_relative "simplecov/combine"
require_relative "simplecov/combine/branches_combiner"
require_relative "simplecov/combine/methods_combiner"
require_relative "simplecov/combine/files_combiner"
require_relative "simplecov/combine/lines_combiner"
require_relative "simplecov/combine/results_combiner"
require_relative "simplecov/useless_results_remover"
require_relative "simplecov/simulate_coverage"

# Load default config
# simplecov:disable — env-var only set by aruba feature tests
require_relative "simplecov/defaults" unless ENV["SIMPLECOV_NO_DEFAULTS"]
