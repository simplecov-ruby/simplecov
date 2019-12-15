# frozen_string_literal: true

module SimpleCov
  #
  # Representation of a source file including it's coverage data, source code,
  # source lines and featuring helpers to interpret that data.
  #
  class SourceFile
    include SimpleCov::Supports::SourceFileSupport
    # Representation of a single line in a source file including
    # this specific line's source code, line_number and code coverage,
    # with the coverage being either nil (coverage not applicable, e.g. comment
    # line), 0 (line not covered) or >1 (the amount of times the line was
    # executed)
    class Line
      # The source code for this line. Aliased as :source
      attr_reader :src
      # The line number in the source file. Aliased as :line, :number
      attr_reader :line_number
      # The coverage data for this line: either nil (never), 0 (missed) or >=1 (times covered)
      attr_reader :coverage
      # Whether this line was skipped
      attr_reader :skipped

      # Lets grab some fancy aliases, shall we?
      alias source src
      alias line line_number
      alias number line_number

      def initialize(src, line_number, coverage)
        raise ArgumentError, "Only String accepted for source" unless src.is_a?(String)
        raise ArgumentError, "Only Integer accepted for line_number" unless line_number.is_a?(Integer)
        raise ArgumentError, "Only Integer and nil accepted for coverage" unless coverage.is_a?(Integer) || coverage.nil?

        @src         = src
        @line_number = line_number
        @coverage    = coverage
        @skipped     = false
      end

      # Returns true if this is a line that should have been covered, but was not
      def missed?
        !never? && !skipped? && coverage.zero?
      end

      # Returns true if this is a line that has been covered
      def covered?
        !never? && !skipped? && coverage.positive?
      end

      # Returns true if this line is not relevant for coverage
      def never?
        !skipped? && coverage.nil?
      end

      # Flags this line as skipped
      def skipped!
        @skipped = true
      end

      # Returns true if this line was skipped, false otherwise. Lines are skipped if they are wrapped with
      # # :nocov: comment lines.
      def skipped?
        !!skipped
      end

      # The status of this line - either covered, missed, skipped or never. Useful i.e. for direct use
      # as a css class in report generation
      def status
        return "skipped" if skipped?
        return "never" if never?
        return "missed" if missed?
        return "covered" if covered?
      end
    end

    #
    # Representing single branch that has been detected in coverage report.
    # Give us support methods that handle needed calculations.
    class Branch
      include SimpleCov::Supports::BranchSupport

      attr_reader :type,
                  :id,
                  :start_line,
                  :start_col,
                  :end_line,
                  :end_col

      attr_accessor :coverage, :root_id

      def initialize(*args)
        @type       = args[0]
        @id         = args[1]
        @start_line = args[2]
        @start_col  = args[3]
        @end_line   = args[4]
        @end_col    = args[5]
        @root_id    = args[6]
        @coverage   = 0
      end

      #
      # Return true if there is relevant count defined > 0
      #
      # @return [Boolean]
      #
      def covered?
        coverage.positive?
      end

      #
      # Check if branche missed or not
      #
      # @return [Boolean]
      #
      def missed?
        coverage.zero?
      end

      #
      # Current branch is root or not
      #
      # @return [Boolean]
      #
      def root?
        root_id.nil?
      end

      #
      # Current branch is sub_branch
      #
      # @return [Boolean]
      #
      def sub_branch?
        !root?
      end

      #
      # Branch is positive or negative.
      # For `case` conditions, `when` always supposed as positive branch.
      # For `if, else` conditions:
      # coverage returns matrices ex: [:if, 0,..] => {[:then, 1,..], [:else, 2,..]},
      # positive branch always has Id equals to root branch Id incremented by 1.
      #
      # @return [Boolean]
      #
      def positive?
        return true if type == :when

        (1 + root_id.to_i) == id
      end

      #
      # Branch is negative
      #
      # @return [Boolean]
      #
      def negative?
        !positive?
      end

      #
      # Return the sign depends on branch is positive or negative
      #
      # @return [String]
      #
      def badge
        positive? ? "+" : "-"
      end
    end

    # The full path to this source file (e.g. /User/colszowka/projects/simplecov/lib/simplecov/source_file.rb)
    attr_reader :filename
    # The array of coverage data received from the Coverage.result
    attr_reader :coverage

    def initialize(filename, coverage)
      @filename = filename.to_s
      @coverage = coverage
    end

    # The path to this source file relative to the projects directory
    def project_filename
      @filename.sub(Regexp.new("^#{Regexp.escape(SimpleCov.root)}"), "")
    end

    # The source code for this file. Aliased as :source
    def src
      # We intentionally read source code lazily to
      # suppress reading unused source code.
      @src ||= File.open(filename, "rb", &:readlines)
    end
    alias source src

    # Returns all source lines for this file as instances of SimpleCov::SourceFile::Line,
    # and thus including coverage data. Aliased as :source_lines
    def lines
      @lines ||= build_lines
    end
    alias source_lines lines

    def build_lines
      coverage_exceeding_source_warn if coverage[:lines].size > src.size
      lines = src.map.with_index(1) do |src, i|
        SimpleCov::SourceFile::Line.new(src, i, coverage[:lines][i - 1])
      end
      process_skipped_lines(lines)
    end

    #
    # Return all the branches inside current source file
    def branches
      @branches ||= build_branches
    end

    # Warning to identify condition from Issue #56
    def coverage_exceeding_source_warn
      warn "Warning: coverage data provided by Coverage [#{coverage[:lines].size}] exceeds number of lines in #{filename} [#{src.size}]"
    end

    # Access SimpleCov::SourceFile::Line source lines by line number
    def line(number)
      lines[number - 1]
    end

    # The coverage for this file in percent. 0 if the file has no coverage lines
    def covered_percent
      return 100.0 if no_lines?

      return 0.0 if relevant_lines.zero?

      Float(covered_lines.size * 100.0 / relevant_lines.to_f)
    end

    def covered_strength
      return 0.0 if relevant_lines.zero?

      (lines_strength / relevant_lines.to_f).round(1)
    end

    def no_lines?
      lines.length.zero? || (lines.length == never_lines.size)
    end

    def lines_strength
      lines.map(&:coverage).compact.reduce(:+)
    end

    def relevant_lines
      lines.size - never_lines.size - skipped_lines.size
    end

    def no_branches?
      total_branches.length.zero?
    end

    def branches_coverage_percent
      return 100.0 if no_branches?
      return 0.0 if covered_branches.size.zero?

      Float(covered_branches.size * 100.0 / total_branches.size.to_f)
    end

    #
    # Return the relevant branches to source file
    def total_branches
      covered_branches + missed_branches
    end

    #
    # Return hash with key of line number and branch coverage count as value
    def branches_report
      @branches_report ||= build_branches_report
    end
  end
end
