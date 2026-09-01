# frozen_string_literal: true

require "digest/sha1"
require "forwardable"
require_relative "result/filter_config"
require_relative "result/missing_source_files_reporter"
require_relative "result/serialization"
require_relative "result/source_file_builder"

module SimpleCov
  #
  # A code coverage result, initialized from the Hash Ruby's built-in coverage
  # library generates.
  #
  class Result
    extend Forwardable
    include Serialization

    attr_reader :original_result, :files
    # Every path the producing process was told to track, loaded or not.
    # Carried into the resultset so a merge elsewhere can inject the ones
    # nobody loaded without needing that process's config (#1250).
    attr_reader :tracked_files
    # Used only for parallel-result coordination. They do not change which
    # fresh suites are merged.
    attr_reader :run_id, :worker_id
    alias_method :source_files, :files
    # The `ContextMap` recorded under `track_tests`, or nil when this result
    # carries none: tracking was off, or a merge dropped the map because not
    # every merged result recorded one.
    attr_reader :contexts

    # The distinct run names behind this result, set by a merge so presentation
    # can say "A and N other runs" instead of reading the joined
    # `command_name` aloud in full. Splitting that string back apart would
    # misread a run name that itself contains a comma.
    attr_writer :created_at, :command_name, :command_names

    def_delegators :files, :covered_percent, :covered_percentages, :least_covered_file, :covered_strength,
      :covered_lines, :missed_lines,
      :total_branches, :covered_branches, :missed_branches,
      :total_methods, :covered_methods, :missed_methods,
      :coverage_statistics, :coverage_statistics_by_file
    def_delegator :files, :lines_of_code, :total_lines

    # `filter_config` defaults to the SimpleCov singleton's filter / group
    # configuration. Pass a custom FilterConfig to opt out, which is useful for
    # tests that build synthetic Results.
    #
    # `tracked_files` accepts any collection that answers `to_a` (the merge
    # passes a Set), and nil for a run that tracked nothing.
    def initialize(original_result, command_name: nil, created_at: nil, not_loaded_files: Set.new,
      tracked_files: nil, run_id: nil, worker_id: nil, contexts: nil, report: false,
      filter_config: FilterConfig.new)
      @original_result = original_result.freeze
      @command_name = command_name
      @created_at = created_at
      initialize_resultset_metadata(tracked_files, run_id, worker_id, contexts)
      @groups_config = filter_config.groups
      builder = SourceFileBuilder.new(original_result, not_loaded_files: not_loaded_files)
      @files = builder.call
      warn_about_missing_source_files(builder.missing_source_files) if report
      apply_cover_filters!(filter_config.cover_filters)
      apply_filters!(filter_config.filters)
    end

    def filenames
      files.map(&:filename)
    end

    # The path is resolved against SimpleCov.root, so callers can pass either
    # an absolute path or a project-relative one.
    def source_file_for(path)
      target = File.expand_path(path, SimpleCov.root)
      files.find { |file| file.filename.eql?(target) }
    end

    # Path resolution as in `source_file_for`.
    def coverage_for(path)
      source_file_for(path)&.coverage_statistics
    end

    def groups
      @groups ||= SimpleCov.grouped(files, groups: @groups_config)
    end

    # Returns nil if formatting has been opted out of (`SimpleCov.formatter
    # false` / `SimpleCov.formatters []`), the cheap path for non-final
    # processes in a parallel CI run, which only need their `.resultset.json`
    # on disk (#964).
    def format!
      formatter = SimpleCov.formatter
      return nil if formatter.nil?

      formatted = Formatter.format(formatter, self)
      # Recorded regardless of how the run ends, so a parent process's
      # clobber-prevention backstop can tell a report was produced even when
      # this run's checks or tests failed, unlike .last_run.json.
      ReportStamp.touch
      formatted
    end

    def created_at
      @created_at ||= Time.now
    end

    def command_name
      @command_name ||= SimpleCov.command_name
    end

    def command_names
      @command_names ||= [command_name]
    end

    def self.from_hash(hash)
      hash.map do |command_name, data|
        new(data.fetch("coverage"), command_name: command_name, created_at: Time.at(data.fetch("timestamp")),
          tracked_files: data["tracked_files"], run_id: data["run_id"],
          worker_id: data["worker_id"], contexts: ContextMap.from_hash(data["contexts"]))
      end
    end

    private

    def initialize_resultset_metadata(tracked_files, run_id, worker_id, contexts)
      @tracked_files = tracked_files.to_a
      @run_id = run_id
      @worker_id = worker_id
      @contexts = contexts
    end

    def warn_about_missing_source_files(missing)
      return if missing.empty?

      # Emit only from the process that writes the final report: the merged
      # result is rebuilt in every parallel worker, so without this gate the
      # warning prints once per worker. Intentionally not gated on
      # print_errors, because the default at_fork sets print_errors false on
      # workers and in many parallel runners the final-report process is itself
      # a worker (#980, #1171).
      return unless SimpleCov.final_result_process?

      # Every built file survives (only the missing ones are dropped), so an
      # empty file list is exactly the "nothing was found" case.
      MissingSourceFilesReporter.new(missing, every_entry_dropped: @files.empty?).warn!
    end

    def apply_filters!(filters)
      filters.each do |filter|
        @files = FileList.new(@files.reject { |source_file| filter.matches?(source_file) })
      end
    end

    # With no cover matchers configured this is a no-op, preserving the
    # historical "everything required, then filtered" universe.
    def apply_cover_filters!(cover_filters)
      return if cover_filters.empty?

      @files = FileList.new(
        @files.select { |source_file| cover_filters.any? { |filter| filter.matches?(source_file) } }
      )
    end
  end
end
