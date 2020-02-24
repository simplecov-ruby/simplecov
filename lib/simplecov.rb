# frozen_string_literal: true

require "English"

# Coverage may be inaccurate under JRUBY.
if defined?(JRUBY_VERSION) && defined?(JRuby)

  # @see https://github.com/jruby/jruby/issues/1196
  # @see https://github.com/metricfu/metric_fu/pull/226
  # @see https://github.com/colszowka/simplecov/issues/420
  # @see https://github.com/colszowka/simplecov/issues/86
  # @see https://jira.codehaus.org/browse/JRUBY-6106

  unless org.jruby.RubyInstanceConfig.FULL_TRACE_ENABLED
    warn 'Coverage may be inaccurate; set the "--debug" command line option,' \
      ' or do JRUBY_OPTS="--debug"' \
      ' or set the "debug.fullTrace=true" option in your .jrubyrc'
  end
end

#
# Code coverage for ruby. Please check out README for a full introduction.
#
module SimpleCov
  class << self
    attr_accessor :running
    attr_accessor :pid
    attr_reader :exit_exception

    # Basically, should we take care of at_exit behavior or something else?
    # Used by the minitest plugin. See lib/minitest/simplecov_plugin.rb
    attr_accessor :external_at_exit
    alias external_at_exit? external_at_exit

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
    def start(profile = nil, &block)
      require "coverage"
      initial_setup(profile, &block)
      @result = nil
      self.pid = Process.pid

      start_coverage_measurement
    end

    #
    # Collate a series of SimpleCov result files into a single SimpleCov output.
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
    def collate(result_filenames, profile = nil, &block)
      raise "There's no reports to be merged" if result_filenames.empty?

      initial_setup(profile, &block)

      results = result_filenames.flat_map do |filename|
        # Re-create each included instance of SimpleCov::Result from the stored run data.
        (JSON.parse(File.read(filename)) || {}).map do |command_name, coverage|
          SimpleCov::Result.from_hash(command_name => coverage)
        end
      end

      # Use the ResultMerger to produce a single, merged result, ready to use.
      @result = SimpleCov::ResultMerger.merge_and_store(*results)

      run_exit_tasks!
    end

    #
    # Returns the result for the current coverage run, merging it across test suites
    # from cache using SimpleCov::ResultMerger if use_merging is activated (default)
    #
    def result
      return @result if result?

      # Collect our coverage result

      process_coverage_result if running

      # If we're using merging of results, store the current result
      # first (if there is one), then merge the results and return those
      if use_merging
        wait_for_other_processes
        SimpleCov::ResultMerger.store_result(@result) if result?
        @result = SimpleCov::ResultMerger.merged_result
      end

      @result
    ensure
      self.running = false
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
      grouped = {}
      grouped_files = []
      groups.each do |name, filter|
        grouped[name] = SimpleCov::FileList.new(files.select { |source_file| filter.matches?(source_file) })
        grouped_files += grouped[name]
      end
      if !groups.empty? && !(other_files = files.reject { |source_file| grouped_files.include?(source_file) }).empty?
        grouped["Ungrouped"] = SimpleCov::FileList.new(other_files)
      end
      grouped
    end

    #
    # Applies the profile of given name on SimpleCov configuration
    #
    def load_profile(name)
      profiles.load(name)
    end

    def load_adapter(name)
      warn "#{Kernel.caller.first}: [DEPRECATION] #load_adapter is deprecated. Use #load_profile instead."
      load_profile(name)
    end

    #
    # Clear out the previously cached .result. Primarily useful in testing
    #
    def clear_result
      @result = nil
    end

    #
    # Capture the current exception if it exists
    # This will get called inside the at_exit block
    #
    def set_exit_exception
      @exit_exception = $ERROR_INFO
    end

    #
    # Returns the exit status from the exit exception
    #
    def exit_status_from_exception
      return SimpleCov::ExitCodes::SUCCESS unless exit_exception

      if exit_exception.is_a?(SystemExit)
        exit_exception.status
      else
        SimpleCov::ExitCodes::EXCEPTION
      end
    end

    def at_exit_behavior
      # If we are in a different process than called start, don't interfere.
      return if SimpleCov.pid != Process.pid

      # If SimpleCov is no longer running then don't run exit tasks
      SimpleCov.run_exit_tasks! if SimpleCov.running
    end

    # @api private
    #
    # Called from at_exit block
    #
    def run_exit_tasks!
      set_exit_exception

      exit_status = SimpleCov.exit_status_from_exception

      SimpleCov.at_exit.call

      # Don't modify the exit status unless the result has already been
      # computed
      exit_status = SimpleCov.process_result(SimpleCov.result, exit_status) if SimpleCov.result?

      # Force exit with stored status (see github issue #5)
      # unless it's nil or 0 (see github issue #281)
      if exit_status&.positive?
        $stderr.printf("SimpleCov failed with exit %<exit_status>d\n", exit_status: exit_status) if print_error_status
        Kernel.exit exit_status
      end
    end

    # @api private
    #
    # Usage:
    #   exit_status = SimpleCov.process_result(SimpleCov.result, exit_status)
    #
    def process_result(result, exit_status)
      return exit_status if exit_status != SimpleCov::ExitCodes::SUCCESS # Existing errors

      covered_percent = result.covered_percent.floor(2)
      result_exit_status = result_exit_status(result, covered_percent)
      write_last_run(covered_percent) if result_exit_status == SimpleCov::ExitCodes::SUCCESS # No result errors
      final_result_process? ? result_exit_status : SimpleCov::ExitCodes::SUCCESS
    end

    # @api private
    #
    # rubocop:disable Metrics/MethodLength
    def result_exit_status(result, covered_percent)
      covered_percentages = result.covered_percentages.map { |percentage| percentage.floor(2) }
      if (minimum_violations = minimum_coverage_violated(result)).any?
        report_minimum_violated(minimum_violations)
        SimpleCov::ExitCodes::MINIMUM_COVERAGE
      elsif covered_percentages.any? { |p| p < SimpleCov.minimum_coverage_by_file }
        $stderr.printf(
          "File (%<file>s) is only (%<least_covered_percentage>.2f%%) covered. This is below the expected minimum coverage per file of (%<min_coverage>.2f%%).\n",
          file: result.least_covered_file,
          least_covered_percentage: covered_percentages.min,
          min_coverage: SimpleCov.minimum_coverage_by_file
        )
        SimpleCov::ExitCodes::MINIMUM_COVERAGE
      elsif (last_run = SimpleCov::LastRun.read)
        coverage_diff = last_run[:result][:covered_percent] - covered_percent
        if coverage_diff > SimpleCov.maximum_coverage_drop
          $stderr.printf(
            "Coverage has dropped by %<drop_percent>.2f%% since the last time (maximum allowed: %<max_drop>.2f%%).\n",
            drop_percent: coverage_diff,
            max_drop: SimpleCov.maximum_coverage_drop
          )
          SimpleCov::ExitCodes::MAXIMUM_COVERAGE_DROP
        else
          SimpleCov::ExitCodes::SUCCESS
        end
      else
        SimpleCov::ExitCodes::SUCCESS
      end
    end
    # rubocop:enable Metrics/MethodLength

    #
    # @api private
    #
    def final_result_process?
      # checking for ENV["TEST_ENV_NUMBER"] to determine if the tess are being run in parallel
      !defined?(ParallelTests) || !ENV["TEST_ENV_NUMBER"] || ParallelTests.number_of_running_processes <= 1
    end

    #
    # @api private
    #
    def wait_for_other_processes
      return unless defined?(ParallelTests) && final_result_process?

      ParallelTests.wait_for_other_processes_to_finish
    end

    #
    # @api private
    #
    def write_last_run(covered_percent)
      SimpleCov::LastRun.write(result: {covered_percent: covered_percent})
    end

  private

    def initial_setup(profile, &block)
      load_profile(profile) if profile
      configure(&block) if block_given?
      self.running = true
    end

    #
    # Trigger Coverage.start depends on given config coverage_criterion
    #
    # With Positive branch it supports all coverage measurement types
    # With Negative branch it supports only line coverage measurement type
    #
    def start_coverage_measurement
      # This blog post gives a good run down of the coverage criterias introduced
      # in Ruby 2.5: https://blog.bigbinary.com/2018/04/11/ruby-2-5-supports-measuring-branch-and-method-coverages.html
      # There is also a nice writeup of the different coverage criteria made in this
      # comment  https://github.com/colszowka/simplecov/pull/692#discussion_r281836176 :
      # Ruby < 2.5:
      # https://github.com/ruby/ruby/blob/v1_9_3_374/ext/coverage/coverage.c
      # traditional mode (Array)
      #
      # Ruby 2.5:
      # https://bugs.ruby-lang.org/issues/13901
      # https://github.com/ruby/ruby/blob/v2_5_3/ext/coverage/coverage.c
      # default: traditional/compatible mode (Array)
      # :lines - like traditional mode but using Hash
      # :branches
      # :methods
      # :all - same as lines + branches + methods
      #
      # Ruby >= 2.6:
      # https://bugs.ruby-lang.org/issues/15022
      # https://github.com/ruby/ruby/blob/v2_6_3/ext/coverage/coverage.c
      # default: traditional/compatible mode (Array)
      # :lines - like traditional mode but using Hash
      # :branches
      # :methods
      # :oneshot_lines - can not be combined with lines
      # :all - same as lines + branches + methods
      #
      if coverage_start_arguments_supported?
        start_coverage_with_criteria
      else
        Coverage.start
      end
    end

    def start_coverage_with_criteria
      start_arguments = coverage_criteria.map do |criterion|
        [lookup_corresponding_ruby_coverage_name(criterion), true]
      end.to_h

      Coverage.start(start_arguments)
    end

    CRITERION_TO_RUBY_COVERAGE = {
      branch: :branches,
      line: :lines
    }.freeze
    def lookup_corresponding_ruby_coverage_name(criterion)
      CRITERION_TO_RUBY_COVERAGE.fetch(criterion)
    end

    #
    # Finds files that were to be tracked but were not loaded and initializes
    # the line-by-line coverage to zero (if relevant) or nil (comments / whitespace etc).
    #
    def add_not_loaded_files(result)
      if tracked_files
        result = result.dup
        Dir[tracked_files].each do |file|
          absolute_path = File.expand_path(file)
          result[absolute_path] ||= SimulateCoverage.call(absolute_path)
        end
      end

      result
    end

    #
    # Call steps that handle process coverage result
    #
    # @return [Hash]
    #
    def process_coverage_result
      adapt_coverage_result
      remove_useless_results
      result_with_not_loaded_files
    end

    #
    # Unite the result so it wouldn't matter what coverage type was called
    #
    # @return [Hash]
    #
    def adapt_coverage_result
      @result = SimpleCov::ResultAdapter.call(Coverage.result)
    end

    #
    # Filter coverage result
    # The result before filter also has result of coverage for files
    # are not related to the project like loaded gems coverage.
    #
    # @return [Hash]
    #
    def remove_useless_results
      @result = SimpleCov::UselessResultsRemover.call(@result)
    end

    #
    # Initialize result with files that are not included by coverage
    # and added inside the config block
    #
    # @return [Hash]
    #
    def result_with_not_loaded_files
      @result = SimpleCov::Result.new(add_not_loaded_files(@result))
    end

    def minimum_coverage_violated(result)
      coverage_achieved = minimum_coverage.map do |criterion, percent|
        {
          criterion: criterion,
          minimum_expected: percent,
          actual: result.coverage_statistics[criterion].percent
        }
      end

      coverage_achieved.select do |achieved|
        achieved.fetch(:actual) < achieved.fetch(:minimum_expected)
      end
    end

    def report_minimum_violated(violations)
      violations.each do |violation|
        $stderr.printf(
          "%<criterion>s coverage (%<covered>.2f%%) is below the expected minimum coverage (%<minimum_coverage>.2f%%).\n",
          covered: violation.fetch(:actual).floor(2),
          minimum_coverage: violation.fetch(:minimum_expected),
          criterion: violation.fetch(:criterion).capitalize
        )
      end
    end
  end
end

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__)))
require "set"
require "forwardable"
require "simplecov/configuration"
SimpleCov.extend SimpleCov::Configuration
require "simplecov/coverage_statistics"
require "simplecov/exit_codes"
require "simplecov/profiles"
require "simplecov/source_file/line"
require "simplecov/source_file/branch"
require "simplecov/source_file"
require "simplecov/file_list"
require "simplecov/result"
require "simplecov/filter"
require "simplecov/formatter"
require "simplecov/last_run"
require "simplecov/lines_classifier"
require "simplecov/result_merger"
require "simplecov/command_guesser"
require "simplecov/version"
require "simplecov/result_adapter"
require "simplecov/combine"
require "simplecov/combine/branches_combiner"
require "simplecov/combine/files_combiner"
require "simplecov/combine/lines_combiner"
require "simplecov/combine/results_combiner"
require "simplecov/useless_results_remover"
require "simplecov/simulate_coverage"

# Load default config
require "simplecov/defaults" unless ENV["SIMPLECOV_NO_DEFAULTS"]
