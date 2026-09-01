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
  class SourceFile
    include BuilderContext

    attr_reader :filename, :coverage_data

    def initialize(filename, coverage_data, loaded: true)
      @filename = filename
      @coverage_data = coverage_data
      @loaded = loaded
    end

    def project_filename
      @filename.delete_prefix(SimpleCov.root).sub(%r{\A[/\\]}, "")
    end

    # Read lazily to suppress reading unused source code.
    def src
      @src ||= SourceLoader.call(filename)
    end
    alias_method :source, :src

    # The per-criterion coverage statistics for this file. With no argument
    # answers the `{line:, branch:, method:}` Hash, and with a criterion symbol
    # that one CoverageStatistics. Every criterion is present even when it
    # wasn't enabled during the run, collapsed to 0/0/0; `FileList` is the
    # layer that filters to the enabled set.
    def coverage_statistics(criterion = nil)
      stats = (@coverage_statistics ||= Statistics.new(self).call)
      criterion ? stats[criterion] : stats
    end

    def lines
      @lines ||= LineBuilder.new(self).call
    end
    alias_method :source_lines, :lines

    def covered_lines
      @covered_lines ||= lines.select(&:covered?)
    end

    def missed_lines
      @missed_lines ||= lines.select(&:missed?)
    end

    def never_lines
      @never_lines ||= lines.select(&:never?)
    end

    def skipped_lines
      @skipped_lines ||= lines.select(&:skipped?)
    end

    def lines_of_code
      coverage_statistics[:line]&.total || 0
    end

    # Answers nil for a number this file has no line for.
    def line(number)
      lines.at(number - 1)
    end

    # Nil if the criterion was not measured.
    def covered_percent(criterion = :line)
      coverage_statistics(criterion)&.percent
    end

    def covered_strength(criterion = :line)
      coverage_statistics(criterion)&.strength
    end

    # Every line the file has is irrelevant, a file with no lines at all
    # included.
    def no_lines?
      lines.all?(&:never?)
    end

    def relevant_lines
      lines.size - never_lines.size - skipped_lines.size
    end

    def branches
      @branches ||= BranchBuilder.new(self).call
    end

    def no_branches?
      total_branches.empty?
    end

    def branches_coverage_percent
      Deprecation.warn("`SimpleCov::SourceFile#branches_coverage_percent` is deprecated. " \
                       "Use `covered_percent(:branch)`.")
      covered_percent(:branch)
    end

    def total_branches
      @total_branches ||= covered_branches + missed_branches
    end

    def branches_report
      @branches_report ||=
        branches.reject(&:skipped?).group_by(&:report_line).transform_values { |bs| bs.map(&:report) }
    end

    # A tree schema, because some conditions like `case` may have an additional
    # `else` that isn't declared in code but is given by default by the
    # coverage report.
    def covered_branches
      @covered_branches ||= branches.select(&:covered?)
    end

    def missed_branches
      @missed_branches ||= branches.select(&:missed?)
    end

    def branches_for_line(line_number)
      branches_report.fetch(line_number, [])
    end

    def line_with_missed_branch?(line_number)
      branches_for_line(line_number).any? { |_type, count| count.zero? }
    end

    def methods
      @methods ||= MethodBuilder.new(self).call
    end

    def covered_methods
      @covered_methods ||= methods.select(&:covered?)
    end

    def missed_methods
      @missed_methods ||= methods.select(&:missed?)
    end

    def methods_coverage_percent
      Deprecation.warn("`SimpleCov::SourceFile#methods_coverage_percent` is deprecated. " \
                       "Use `covered_percent(:method)`.")
      covered_percent(:method)
    end

    def not_loaded?
      !@loaded
    end
  end
end
