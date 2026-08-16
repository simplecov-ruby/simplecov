# frozen_string_literal: true

require "digest/sha1"
require "forwardable"
require_relative "result/missing_source_files_reporter"
require_relative "result/source_file_builder"

module SimpleCov
  #
  # A simplecov code coverage result, initialized from the Hash Ruby's built-in coverage
  # library generates (Coverage.result).
  #
  # rubocop:disable Metrics/ClassLength -- one data object together with
  # its resultset-entry serialization; splitting would scatter that shape
  class Result
    extend Forwardable

    # Returns the original Coverage.result used for this instance of SimpleCov::Result
    attr_reader :original_result
    # Every path the producing process was told to track, loaded or not. Carried
    # into the resultset so a merge elsewhere can inject the ones nobody loaded
    # without needing that process's `cover` / `track_files` config. See #1250.
    attr_reader :tracked_files
    # Parallel-run coordination identities, plus the per-test context
    # recording (a TestContexts::Map, or nil).
    attr_reader :run_id, :worker_id, :test_contexts
    # Returns all files that are applicable to this result (sans filters!) as instances of
    # SimpleCov::SourceFile. Aliased as :source_files
    attr_reader :files
    alias source_files files
    # Explicitly set the Time this result has been created
    attr_writer :created_at
    # Explicitly set the command name that was used for this coverage result. Defaults to SimpleCov.command_name
    attr_writer :command_name

    def_delegators :files, :covered_percent, :covered_percentages, :least_covered_file, :covered_strength,
                   :covered_lines, :missed_lines,
                   :total_branches, :covered_branches, :missed_branches,
                   :total_methods, :covered_methods, :missed_methods,
                   :coverage_statistics, :coverage_statistics_by_file
    def_delegator :files, :lines_of_code, :total_lines

    # Bundles the filter and grouping configuration a Result applies to its
    # source files after building them. Each field defaults to the SimpleCov
    # singleton's configuration, so ordinary callers never construct one;
    # tests pass a custom instance to opt out of (or extend) the project's
    # filters or groups (e.g. `filters: []` to keep every file). Grouping the
    # three together keeps Result#initialize's parameter list small.
    class FilterConfig
      attr_reader :filters, :cover_filters, :groups

      def initialize(filters: SimpleCov.filters, cover_filters: SimpleCov.cover_filters, groups: SimpleCov.groups)
        @filters = filters
        @cover_filters = cover_filters
        @groups = groups
      end
    end

    # Initialize a new SimpleCov::Result from given Coverage.result (a Hash of filenames each containing an array of
    # coverage data).
    #
    # `filter_config` defaults to the SimpleCov singleton's filter / group
    # configuration so existing call sites are unchanged. Pass a custom
    # FilterConfig to opt out — useful for tests that build synthetic Results
    # and don't want the project's filters or groups applied.
    def initialize(original_result, command_name: nil, created_at: nil, not_loaded_files: Set.new,
                   tracked_files: [], run_id: nil, worker_id: nil, report: false, filter_config: FilterConfig.new,
                   test_contexts: nil)
      @original_result = original_result.freeze
      @command_name = command_name
      @created_at = created_at
      initialize_coordination_metadata(tracked_files, run_id, worker_id, test_contexts)
      @groups_config = filter_config.groups
      builder = SourceFileBuilder.new(original_result, not_loaded_files: not_loaded_files)
      @files = builder.call
      warn_about_missing_source_files(builder.missing_source_files, original_result.size) if report
      apply_cover_filters!(filter_config.cover_filters)
      apply_filters!(filter_config.filters)
    end

    # Returns all filenames for source files contained in this result
    def filenames
      files.map(&:filename)
    end

    # Returns the SimpleCov::SourceFile for the given path, or nil if no
    # matching file is in this result. The path is resolved against
    # SimpleCov.root, so callers can pass either an absolute path or a
    # project-relative one.
    def source_file_for(path)
      target = File.expand_path(path, SimpleCov.root)
      files.find { |file| file.filename == target }
    end

    # Returns the {line:/branch:/method:} coverage_statistics hash for the
    # given file path, or nil if no matching source file is in this
    # result. See SimpleCov::Result#source_file_for for path resolution.
    def coverage_for(path)
      source_file_for(path)&.coverage_statistics
    end

    # Returns a Hash of groups for this result. Define groups using SimpleCov.group 'Models', 'app/models'
    def groups
      @groups ||= SimpleCov.grouped(files, groups: @groups_config)
    end

    # Applies the configured SimpleCov.formatter on this result. Returns
    # nil if formatting has been opted out of (`SimpleCov.formatter false`
    # / `SimpleCov.formatters []`) — the cheap path for non-final
    # processes in a parallel CI run, which only need their
    # `.resultset.json` on disk. See #964.
    def format!
      formatter = SimpleCov.formatter
      return nil if formatter.nil?

      formatted = Formatter.format(formatter, self)
      # Recorded regardless of how the run ends, so a parent process's
      # clobber-prevention backstop can tell a report was produced even
      # when this run's checks or tests failed (unlike .last_run.json,
      # which only successful runs write).
      SimpleCov::ReportStamp.touch
      formatted
    end

    # Defines when this result has been created. Defaults to Time.now
    def created_at
      @created_at ||= Time.now
    end

    # The command name that launched this result.
    # Delegated to SimpleCov.command_name if not set manually
    def command_name
      @command_name ||= SimpleCov.command_name
    end

    # Returns a hash representation of this Result that can be used for marshalling it into JSON
    def to_hash
      data = {"coverage" => coverage, "timestamp" => created_at.to_f} #: Hash[String, untyped]
      data["run_id"] = run_id if run_id
      data["worker_id"] = worker_id if worker_id
      # Omitted when empty so a run that tracks nothing writes the shape it
      # always has, and so the key only appears where it carries information.
      data["tracked_files"] = tracked_files unless tracked_files.empty?
      attach_test_contexts(data)
      {command_name => data}
    end

    # Loads a SimpleCov::Result#to_hash dump
    def self.from_hash(hash)
      hash.map do |command_name, data|
        new(data.fetch("coverage"), command_name: command_name, created_at: Time.at(data["timestamp"]),
                                    tracked_files: data["tracked_files"] || [], run_id: data["run_id"],
                                    worker_id: data["worker_id"], test_contexts: TestContexts::Map.from_hash(data["test_contexts"]))
      end
    end

  private

    def initialize_coordination_metadata(tracked_files, run_id, worker_id, test_contexts)
      @tracked_files = tracked_files.to_a
      @run_id = run_id
      @worker_id = worker_id
      @test_contexts = test_contexts
    end

    # Written even when empty: presence tells the merge attribution was
    # recorded, and an absent key on any entry drops the merged recording.
    def attach_test_contexts(data)
      data["test_contexts"] = test_contexts.slice(filenames).to_h if test_contexts
    end

    def warn_about_missing_source_files(missing, input_size)
      return if missing.empty?

      # Emit only from the process that writes the final report. The merged
      # result is rebuilt in every parallel worker (each one stores its own
      # slice), so without this gate the warning prints once per worker — this
      # is the same signal SimpleCov uses to pick the process that runs the
      # report and threshold checks. It's intentionally not gated on
      # print_errors: the default at_fork sets print_errors false on workers,
      # and in many parallel runners the final-report process is itself a
      # worker, so a print_errors gate would suppress the one warning we want.
      # See issues #980 and #1171.
      return unless SimpleCov.final_result_process?

      MissingSourceFilesReporter.new(
        missing,
        input_size: input_size,
        every_entry_dropped: @files.empty? && missing.size == input_size
      ).warn!
    end

    # A live result's criterion keys are Symbols (`:lines`, `:branches`),
    # while entries parsed back from `.resultset.json` carry Strings, and
    # the combiners read only String keys. Serialize with String keys so a
    # live result merged against a stored entry contributes its counts
    # instead of being silently dropped for every shared file.
    def coverage
      original_result.slice(*filenames).transform_values do |file_coverage|
        file_coverage.transform_keys(&:to_s)
      end
    end

    # Applies the given filter chain to `@files`, dropping each source
    # file that any filter matches.
    def apply_filters!(filters)
      filters.each do |filter|
        @files = SimpleCov::FileList.new(@files.reject { |source_file| filter.matches?(source_file) })
      end
    end

    # When any `cover` matcher is configured, restrict `@files` to source
    # files matching at least one of them. With no cover matchers configured
    # this is a no-op, preserving the historical "everything required, then
    # filtered" universe.
    def apply_cover_filters!(cover_filters)
      return if cover_filters.empty?

      @files = SimpleCov::FileList.new(
        @files.select { |source_file| cover_filters.any? { |filter| filter.matches?(source_file) } }
      )
    end
  end
  # rubocop:enable Metrics/ClassLength
end
