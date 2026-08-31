# frozen_string_literal: true

require "forwardable"
require_relative "simplecov/current_run"

module SimpleCov
  class ConfigurationError < StandardError; end

  # At module scope rather than inside `class << self` so it can be declared in
  # the RBS signatures; lexical scoping keeps references inside the singleton
  # class working.
  CRITERION_TO_RUBY_COVERAGE = {
    branch: :branches,
    line: :lines,
    method: :methods,
    oneshot_line: :oneshot_lines
  }.freeze

  # `SingleForwardable` rather than `Forwardable` on the singleton class,
  # because RBS has no way to speak about the singleton class's own ancestors.
  extend SingleForwardable

  def_delegators :current_run,
                 :pid, :pid=, :process_start_time, :process_start_time=,
                 :subprocess_serial, :next_subprocess_serial!,
                 :forked_subprocess?, :mark_forked_subprocess!,
                 :result?, :collating_result?

  class << self
    def current_run
      @current_run ||= CurrentRun.new
    end

    # @api private
    attr_writer :current_run

    attr_accessor :external_at_exit

    # `:oneshot_line` data is folded into the `:line` bucket of
    # `coverage_statistics` by `ResultAdapter`. The cast is steep's: it narrows
    # a union on `==` but not on `equal?`.
    def coverage_statistics_key(criterion)
      criterion.equal?(:oneshot_line) ? :line : _ = criterion
    end

    # Coerced so rspec-mocks 4's predicate matcher accepts the result.
    def external_at_exit?
      !!@external_at_exit
    end

    def start(profile = nil, &)
      warn_about_start_in_dot_simplecov if @autoloading_dot_simplecov

      initial_setup(profile, &)
      start_tracking
      install_at_exit_hook
    end

    # @api private
    def with_dot_simplecov_autoload
      previous = @autoloading_dot_simplecov # : bool?
      @autoloading_dot_simplecov = true
      yield
    ensure
      # @type var previous: bool?
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

    def install_at_exit_hook
      return if @at_exit_hook_installed

      @at_exit_hook_installed = true
      # Never defer in a forked child: Minitest pins its after_run at_exit to
      # the pid that armed autorun, so the deferral target can't fire there and
      # the child's resultset would be silently dropped (#1227).
      defer_to_minitest_after_run if minitest_autorun_pending? && !forked_subprocess?
      Kernel.at_exit do
        next if external_at_exit?

        at_exit_behavior
      end
    end

    def start_tracking
      require "coverage"
      warn_if_jruby_full_trace_disabled
      validate_coverage_criteria!
      require_relative "simplecov/process" if enabled_for_subprocesses? && Process.respond_to?(:_fork)

      # Must happen before any forks.
      RunIdentity.prepare

      self.current_run = current_run.successor
      self.pid = Process.pid
      self.process_start_time = Time.now

      start_coverage_measurement
    end

  private

    def start_coverage_measurement
      start_arguments = coverage_criteria.to_h do |criterion|
        [CRITERION_TO_RUBY_COVERAGE.fetch(criterion), true]
      end

      start_arguments[:eval] = true if coverage_for_eval_enabled?

      Coverage.start(**start_arguments) unless Coverage.running?
      start_test_tracking
    end

    # `Rake::TestTask` runs `ruby -e 'require "minitest/autorun"; ...'`, so
    # Minitest's at_exit registers before SimpleCov's and, at_exit being LIFO,
    # SimpleCov's would format an empty resultset before the tests ever run.
    # Routing through `Minitest.after_run` instead fires after the suite
    # completes (#1099, #1112).
    def minitest_autorun_pending?
      return false unless defined?(Minitest) && Minitest.respond_to?(:after_run)
      return false unless Minitest.class_variable_defined?(:@@installed_at_exit)

      Minitest.class_variable_get(:@@installed_at_exit)
    end

    def defer_to_minitest_after_run
      self.external_at_exit = true
      Minitest.after_run { at_exit_behavior }
    end

    # JRuby coverage data is unreliable unless full-trace mode is enabled.
    # @see https://github.com/jruby/jruby/issues/1196
    # @see https://github.com/simplecov-ruby/simplecov/issues/420
    # @see https://github.com/simplecov-ruby/simplecov/issues/86
    # mutant:disable — every line below the guard is JRuby-only, and no
    # example running on the engine this suite runs on can reach one.
    def warn_if_jruby_full_trace_disabled
      return unless defined?(JRUBY_VERSION) && defined?(JRuby) # simplecov:disable — JRuby-only branch

      # simplecov:disable — JRuby-only branches; unreachable from CRuby
      # `org` is JRuby's Java-package entry point, absent on CRuby, so no RBS
      # declaration can be truthful here.
      return if org.jruby.RubyInstanceConfig.FULL_TRACE_ENABLED # steep:ignore NoMethod

      warn 'Coverage may be inaccurate; set the "--debug" command line option, ' \
           'or do JRUBY_OPTS="--debug" ' \
           'or set the "debug.fullTrace=true" option in your .jrubyrc'
      # simplecov:enable
    end
  end
end

require_relative "simplecov/color"
require_relative "simplecov/deprecation"
require_relative "simplecov/group_names"
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
require_relative "simplecov/history"
require_relative "simplecov/report_stamp"
require_relative "simplecov/baseline"
require_relative "simplecov/lines_classifier"
require_relative "simplecov/context_map"
require_relative "simplecov/context_map/union"
require_relative "simplecov/test_tracker/constant_watch"
require_relative "simplecov/test_tracker/delta"
require_relative "simplecov/test_tracker"
require_relative "simplecov/test_tracker/framework_hooks"
require_relative "simplecov/test_tracker/accessors"
SimpleCov.extend SimpleCov::TestTracker::Accessors
require_relative "simplecov/result_merger"
require_relative "simplecov/parallel_result_merger"
require_relative "simplecov/parallel_adapters"
require_relative "simplecov/run_identity"
SimpleCov.extend SimpleCov::RunIdentity::Accessors
require_relative "simplecov/command_guesser"
require_relative "simplecov/version"
require_relative "simplecov/result_adapter"
require_relative "simplecov/combine"
require_relative "simplecov/combine/identity_interner"
require_relative "simplecov/combine/branches_combiner"
require_relative "simplecov/combine/methods_combiner"
require_relative "simplecov/combine/lines_combiner"
require_relative "simplecov/combine/coverage_accumulator"
require_relative "simplecov/combine/results_combiner"
require_relative "simplecov/useless_results_remover"
require_relative "simplecov/simulate_coverage"
require_relative "simplecov/unloaded_file_injector"
require_relative "simplecov/view_coverage"
require_relative "simplecov/result_processing"
require_relative "simplecov/exit_handling"
require_relative "simplecov/report_deferral"
require_relative "simplecov/parallel_coordination"

# simplecov:disable — env-var never set in the dogfooded test process
# (sandbox fixture subprocesses set it via simplecov/no_defaults)
require_relative "simplecov/defaults" unless ENV["SIMPLECOV_NO_DEFAULTS"]
