# frozen_string_literal: true

require_relative "directive"
require_relative "static_coverage_extractor"
require_relative "source_file/ruby_data_parser"
require_relative "source_file/source_loader"
require_relative "source_file/skip_chunks"
require_relative "source_file/builder_context"
require_relative "source_file/line_builder"
require_relative "source_file/branch_builder"
require_relative "source_file/method_builder"
require_relative "source_file/statistics"

module SimpleCov
  #
  # Representation of a source file including it's coverage data, source code,
  # source lines and featuring helpers to interpret that data.
  #
  class SourceFile
    include BuilderContext

    # The full path to this source file (e.g. /User/colszowka/projects/simplecov/lib/simplecov/source_file.rb)
    attr_reader :filename
    # The array of coverage data received from the Coverage.result
    attr_reader :coverage_data

    def initialize(filename, coverage_data, loaded: true)
      @filename = filename
      @coverage_data = coverage_data
      @loaded = loaded
    end

    # The path to this source file relative to the projects directory
    def project_filename
      @filename.delete_prefix(SimpleCov.root).sub(%r{\A[/\\]}, "")
    end

    # The source code for this file. Aliased as :source.
    # Intentionally read lazily to suppress reading unused source code.
    def src
      @src ||= SourceLoader.call(filename)
    end
    alias source src

    # Returns a hash keyed by every supported coverage criterion. Each
    # value is a CoverageStatistics, even for criteria that weren't
    # enabled during the run — those collapse to 0/0/0. Consumers
    # (FileList, formatters) decide which keys to surface based on
    # `SimpleCov.coverage_criterion_enabled?`.
    # The per-criterion coverage statistics for this file. With no argument
    # returns the `{line:, branch:, method:}` Hash; pass a criterion symbol
    # (`:line` / `:branch` / `:method`) to get that one CoverageStatistics.
    def coverage_statistics(criterion = nil)
      @coverage_statistics ||= Statistics.new(self).call
      criterion ? @coverage_statistics[criterion] : @coverage_statistics
    end

    # Returns all source lines for this file as instances of SimpleCov::SourceFile::Line,
    # and thus including coverage data. Aliased as :source_lines
    def lines
      @lines ||= LineBuilder.new(self).call
    end
    alias source_lines lines

    # Returns all covered lines as SimpleCov::SourceFile::Line
    def covered_lines
      @covered_lines ||= lines.select(&:covered?)
    end

    # Returns all lines that should have been, but were not covered
    # as instances of SimpleCov::SourceFile::Line
    def missed_lines
      @missed_lines ||= lines.select(&:missed?)
    end

    # Returns all lines that are not relevant for coverage as
    # SimpleCov::SourceFile::Line instances
    def never_lines
      @never_lines ||= lines.select(&:never?)
    end

    # Returns all lines that were skipped as SimpleCov::SourceFile::Line instances
    def skipped_lines
      @skipped_lines ||= lines.select(&:skipped?)
    end

    # Returns the number of relevant lines (covered + missed)
    def lines_of_code
      coverage_statistics[:line]&.total || 0
    end

    # Access SimpleCov::SourceFile::Line source lines by line number
    def line(number)
      lines[number - 1]
    end

    # The coverage for this file in percent, for the given criterion (line by
    # default). Returns nil if the criterion was not measured.
    def covered_percent(criterion = :line)
      coverage_statistics(criterion)&.percent
    end

    def covered_strength(criterion = :line)
      coverage_statistics(criterion)&.strength
    end

    def no_lines?
      lines.empty? || (lines.length == never_lines.size)
    end

    def relevant_lines
      lines.size - never_lines.size - skipped_lines.size
    end

    # Return all the branches inside current source file
    def branches
      @branches ||= BranchBuilder.new(self).call
    end

    def no_branches?
      total_branches.empty?
    end

    # DEPRECATED: use `covered_percent(:branch)`.
    def branches_coverage_percent
      SimpleCov::Deprecation.warn("`SimpleCov::SourceFile#branches_coverage_percent` is deprecated. " \
                                  "Use `covered_percent(:branch)`.")
      covered_percent(:branch)
    end

    # Return the relevant branches to source file
    def total_branches
      @total_branches ||= covered_branches + missed_branches
    end

    # Return hash with key of line number and branch coverage count as value
    def branches_report
      @branches_report ||=
        branches.reject(&:skipped?).group_by(&:report_line).transform_values { |bs| bs.map(&:report) }
    end

    # Select the covered branches. We use a tree schema here because
    # some conditions like `case` may have an additional `else` that
    # isn't declared in code but is given by default by the coverage
    # report.
    def covered_branches
      @covered_branches ||= branches.select(&:covered?)
    end

    # Select the missed branches with coverage equal to zero
    def missed_branches
      @missed_branches ||= branches.select(&:missed?)
    end

    def branches_for_line(line_number)
      branches_report.fetch(line_number, [])
    end

    # Check if any branches missing on given line number
    def line_with_missed_branch?(line_number)
      branches_for_line(line_number).any? { |_type, count| count.zero? }
    end

    # Return all methods detected in this source file
    def methods
      @methods ||= MethodBuilder.new(self).call
    end

    def covered_methods
      @covered_methods ||= methods.select(&:covered?)
    end

    def missed_methods
      @missed_methods ||= methods.select(&:missed?)
    end

    # DEPRECATED: use `covered_percent(:method)`.
    def methods_coverage_percent
      SimpleCov::Deprecation.warn("`SimpleCov::SourceFile#methods_coverage_percent` is deprecated. " \
                                  "Use `covered_percent(:method)`.")
      covered_percent(:method)
    end

    # Whether this file was added via track_files but never loaded/required.
    def not_loaded?
      !@loaded
    end
  end
end
