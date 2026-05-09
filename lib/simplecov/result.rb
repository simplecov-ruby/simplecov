# frozen_string_literal: true

require "digest/sha1"
require "forwardable"

module SimpleCov
  #
  # A simplecov code coverage result, initialized from the Hash Ruby's built-in coverage
  # library generates (Coverage.result).
  #
  class Result
    extend Forwardable

    # Returns the original Coverage.result used for this instance of SimpleCov::Result
    attr_reader :original_result
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

    # Initialize a new SimpleCov::Result from given Coverage.result (a Hash of filenames each containing an array of
    # coverage data).
    #
    # `filters` defaults to the singleton's configured filter chain
    # (`SimpleCov.filters`) so existing call sites are unchanged. Pass an
    # empty array to opt out — useful for tests that build synthetic
    # Results and don't want the project's filters applied. `groups`
    # behaves the same way against `SimpleCov.groups`.
    def initialize(original_result, command_name: nil, created_at: nil, not_loaded_files: Set.new,
                   filters: SimpleCov.filters, groups: SimpleCov.groups)
      result = original_result
      @original_result = result.freeze
      @command_name = command_name
      @created_at = created_at
      @groups_config = groups
      @files = SimpleCov::FileList.new(
        result.filter_map { |filename, coverage| build_source_file(filename, coverage, not_loaded_files) }
              .sort_by(&:filename)
      )
      apply_filters!(filters)
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

    # Returns a Hash of groups for this result. Define groups using SimpleCov.add_group 'Models', 'app/models'
    def groups
      @groups ||= apply_groups
    end

    # Applies the configured SimpleCov.formatter on this result
    def format!
      SimpleCov.formatter.new.format(self)
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
      {
        command_name => {
          "coverage" => coverage,
          "timestamp" => created_at.to_i
        }
      }
    end

    # Loads a SimpleCov::Result#to_hash dump
    def self.from_hash(hash)
      hash.map do |command_name, data|
        new(data.fetch("coverage"), command_name: command_name, created_at: Time.at(data["timestamp"]))
      end
    end

  private

    def build_source_file(filename, coverage, not_loaded_files)
      return unless File.file?(filename)

      SimpleCov::SourceFile.new(
        filename,
        JSON.parse(JSON.dump(coverage)),
        loaded: !not_loaded_files.include?(filename)
      )
    end

    def coverage
      keys = original_result.keys & filenames
      keys.zip(original_result.values_at(*keys)).to_h
    end

    # Applies the given filter chain to `@files`, dropping each source
    # file that any filter matches.
    def apply_filters!(filters)
      filters.each do |filter|
        @files = SimpleCov::FileList.new(@files.reject { |source_file| filter.matches?(source_file) })
      end
    end

    # Build the per-group FileLists from `@groups_config`, plus the
    # implicit "Ungrouped" bucket for files that no group filter
    # matched.
    def apply_groups
      return {} if @groups_config.empty?

      grouped = @groups_config.transform_values do |filter|
        SimpleCov::FileList.new(files.select { |source_file| filter.matches?(source_file) })
      end

      in_group  = grouped.values.flat_map(&:to_a)
      ungrouped = files.reject { |source_file| in_group.include?(source_file) }
      grouped["Ungrouped"] = SimpleCov::FileList.new(ungrouped) if ungrouped.any?

      grouped
    end
  end
end
