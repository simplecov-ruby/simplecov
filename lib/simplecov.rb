# frozen_string_literal: true

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

    attr_accessor :pid
    # When this process started tracking coverage. Captured by SimpleCov.start
    # so JSONFormatter can detect when an existing coverage.json was written
    # by a sibling process running concurrently.
    attr_accessor :process_start_time

    # A monotonically increasing serial the parent assigns to each forked
    # subprocess (see SimpleCov::ProcessForkHook). The default `at_fork`
    # builds the worker's command_name from this rather than the OS pid:
    # the serial sequence is the same from one run to the next, so a re-run
    # overwrites the previous run's resultset entries instead of writing
    # uniquely-named ones that pile up until merge_timeout. See issue #1171.
    def subprocess_serial
      @subprocess_serial ||= 0
    end

    # @api private — bump the serial in the parent before a fork so the
    # child inherits its own ordinal via copy-on-write.
    def next_subprocess_serial!
      @subprocess_serial = subprocess_serial + 1
    end

    # @api private — true in a process that was forked while coverage was
    # running (set by SimpleCov::ProcessForkHook in the child). Such a child
    # stores its own slice but must not act as the final-result process: the
    # process that forked it merges every slice and produces the report. Only
    # consulted when no parallel-test adapter is active, since adapters answer
    # `first_worker?` themselves. See issue #1171.
    def forked_subprocess?
      !!(defined?(@forked_subprocess) && @forked_subprocess)
    end

    # @api private — marked in the child immediately after a fork.
    def mark_forked_subprocess!
      @forked_subprocess = true
    end
    # Should we take care of at_exit behavior or something else? Used by the
    # minitest plugin. See lib/minitest/simplecov_plugin.rb.
    attr_accessor :external_at_exit

    # `:oneshot_line` data is folded into the `:line` bucket of
    # `coverage_statistics` by `ResultAdapter`, so use `:line` to look
    # up stats for either criterion.
    def coverage_statistics_key(criterion)
      criterion == :oneshot_line ? :line : criterion
    end

    # Coerce to a proper boolean so rspec-mocks 4's predicate matcher
    # (`expect(...).not_to be_external_at_exit`) accepts the result.
    def external_at_exit?
      !!@external_at_exit
    end

    #
    # Sets up SimpleCov to run against your project. See README for
    # the full DSL, or:
    #
    #     SimpleCov.start
    #     SimpleCov.start 'rails'                # using a profile
    #     SimpleCov.start { add_filter 'test' }  # with a config block
    #
    def start(profile = nil, &)
      warn_about_start_in_dot_simplecov if @autoloading_dot_simplecov

      initial_setup(profile, &)
      start_tracking
      install_at_exit_hook
    end

    # @api private
    #
    # Mark the duration of a `.simplecov` auto-load so any `SimpleCov.start`
    # call inside the file can warn about the impending migration to a
    # config-only file. Tracking still begins for backward compatibility;
    # the warning is the cue to move `SimpleCov.start` into a test helper.
    # See #581.
    def with_dot_simplecov_autoload
      previous = @autoloading_dot_simplecov
      @autoloading_dot_simplecov = true
      yield
    ensure
      @autoloading_dot_simplecov = previous
    end

    def warn_about_start_in_dot_simplecov
      return if @dot_simplecov_start_warned

      @dot_simplecov_start_warned = true
      warn "[DEPRECATION] Calling `SimpleCov.start` from `.simplecov` is deprecated and will " \
           "be removed in a future release. `.simplecov` should contain configuration only; " \
           "move the `SimpleCov.start` call into your `spec_helper.rb` / `test_helper.rb`. " \
           "Coverage tracking still begins for backward compatibility, but a future release " \
           "will require the explicit `SimpleCov.start` from a test helper. " \
           "See https://github.com/simplecov-ruby/simplecov/issues/581."
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

      # Trigger adapter selection now so the (possibly lazy) parallel_tests
      # gem load happens at start_tracking time rather than mid-suite.
      # `current` is memoized; subsequent calls are cheap.
      SimpleCov::ParallelAdapters.current

      @result = nil
      self.pid = Process.pid
      self.process_start_time = Time.now

      start_coverage_measurement
    end

  private

    #
    # Trigger Coverage.start with the configured criteria. Every supported
    # runtime (CRuby >= 3.1, JRuby >= 9.4, TruffleRuby >= 22) accepts the
    # criteria-hash form, so no compatibility fallback is needed.
    #
    def start_coverage_measurement
      start_arguments = coverage_criteria.to_h do |criterion|
        [CRITERION_TO_RUBY_COVERAGE.fetch(criterion), true]
      end

      start_arguments[:eval] = true if coverage_for_eval_enabled?

      Coverage.start(start_arguments) unless Coverage.running?
    end

    # `Rake::TestTask` runs `ruby -e 'require "minitest/autorun"; ...'`,
    # which means Minitest's at_exit registers before SimpleCov's. Since
    # at_exit fires LIFO, SimpleCov's hook would otherwise run *before*
    # Minitest gets a chance to invoke the tests — and format an empty
    # resultset. When we can see that Minitest is loaded and its autorun
    # is armed, route the report through `Minitest.after_run` instead,
    # which fires after the suite completes. See issues #1099 and #1112.
    def minitest_autorun_pending?
      return false unless defined?(Minitest) && Minitest.respond_to?(:after_run)
      return false unless Minitest.class_variable_defined?(:@@installed_at_exit)

      Minitest.class_variable_get(:@@installed_at_exit)
    end

    def defer_to_minitest_after_run
      self.external_at_exit = true
      Minitest.after_run { SimpleCov.at_exit_behavior }
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

# requires are down here for a load order reason I'm not sure what it is about
require "set"
require "forwardable"
require_relative "simplecov/color"
require_relative "simplecov/deprecation"
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
require_relative "simplecov/parallel_adapters"
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
require_relative "simplecov/result_processing"
require_relative "simplecov/exit_handling"
require_relative "simplecov/parallel_coordination"

# Load default config
# simplecov:disable — env-var only set by aruba feature tests
require_relative "simplecov/defaults" unless ENV["SIMPLECOV_NO_DEFAULTS"]
