# frozen_string_literal: true

module SimpleCov
  #
  # Representation of a source file including it's coverage data, source code,
  # source lines and featuring helpers to interpret that data.
  #
  class SourceFile # rubocop:disable Metrics/ClassLength
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
        !never? && !skipped? && coverage > 0
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
      attr_reader :type,
                  :id,
                  :start_line,
                  :start_col,
                  :end_line,
                  :end_col

      attr_accessor :coverage, :root_id

      def initialize(*branch_attrs, root_id)
        @type, @id, @start_line, @start_col, @end_col, @end_col = *branch_attrs
        @coverage   = 0
        @root_id    = root_id
      end

      #
      # Return true if there is relevant count defined > 0
      #
      # @return [Boolean]
      #
      def covered?
        coverage > 0
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
      #
      # @return [Boolean]
      #
      def positive?
        return true if type == :when
        1 + root_id == id
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

      #
      # Return array of sub branches of current branches
      #
      # @param [Array] branches
      #
      # @return [Array]
      #
      def sub_branches(branches)
        if type == :case
          case_branches(branches)
        else
          branches.select do |branch|
            id == branch.root_id
          end
        end
      end

      #
      # Case/When/Else have special branches behave because
      # `else` branch type is always present no matter if it's declared in code or not
      # => `else` declared start_line != root_branch_line
      # => `else` not declared start_line == root_branch_line
      # for this case we ignore if it's not declared becase it's useless
      #
      # @return [Array]
      #
      def case_branches(branches)
        branches.select do |branch|
          id == branch.root_id && branch.start_line != start_line
        end
      end

      #
      # Return true of false depends on number of start_line
      # If the are in one line start line is same for all
      #
      # @return [Boolean]
      #
      def inline_branch?(branches)
        return false unless root?
        sub_branches(branches).map(&:start_line).uniq.size == 1
      end

      #
      # Return array with coverage count and badge
      #
      # @return [Array]
      #
      def report
        [coverage, badge]
      end
    end

    # The full path to this source file (e.g. /User/colszowka/projects/simplecov/lib/simplecov/source_file.rb)
    attr_reader :filename
    # The array of coverage data received from the Coverage.result
    attr_reader :coverage

    def initialize(filename, coverage)
      @filename = filename
      @coverage = coverage
    end

    # The path to this source file relative to the projects directory
    def project_filename
      @filename.sub(/^#{SimpleCov.root}/, "")
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
    #
    # @return [Array]
    #
    def branches
      @branches ||= build_branches
    end

    # Warning to identify condition from Issue #56
    def coverage_exceeding_source_warn
      $stderr.puts "Warning: coverage data provided by Coverage [#{coverage.size}] exceeds number of lines in #{filename} [#{src.size}]"
    end

    # Access SimpleCov::SourceFile::Line source lines by line number
    def line(number)
      lines[number - 1]
    end

    # The coverage for this file in percent. 0 if the file has no relevant lines
    def covered_percent
      return 100.0 if no_lines?

      return 0.0 if relevant_lines.zero?

      Float(covered_lines.size * 100.0 / relevant_lines.to_f)
    end

    def covered_strength
      return 0.0 if relevant_lines.zero?

      round_float(lines_strength / relevant_lines.to_f, 1)
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
      covered_lines.size + missed_lines.size
    end

    # Will go through all source files and mark lines that are wrapped within # :nocov: comment blocks
    # as skipped.
    def process_skipped_lines(lines)
      skipping = false

      lines.each do |line|
        if SimpleCov::LinesClassifier.no_cov_line?(line.src)
          skipping = !skipping
          line.skipped!
        elsif skipping
          line.skipped!
        end
      end
    end

    def no_branches?
      total_branches.length.zero?
    end

    def branches_coverage_precent
      return 100.0 if no_branches?

      return 0.0 if covered_branches.length.zero?

      Float(covered_branches.size * 100.0 / total_branches.size.to_f)
    end

    #
    # Return the relevant branches to source file
    #
    # @return [Array]
    #
    def total_branches
      covered_branches + missed_branches
    end

    #
    # Return hash with key of line number and branch coverage count as value
    #
    # @return [Hash]
    #
    def branches_report
      @branches_report ||= build_branches_report
    end

    #
    # Call recursive method that transform our static hash to array of objects
    # @return [Array]
    #
    def build_branches
      branches_collection(coverage[:branches] || {})
    end

    #
    # Recursive method brings all of the branches as array of objects,
    # supported with root branch or not depends on it's value
    #
    # ex: { [:if, 0, 4, 2, 10, 5] => { [:then, 1, 5, 4, 6, 13] => 0,  [:else, 2, 8, 4, 9, 18]=>1 } }
    # - root branch: [:if, 0, 4, 2, 10, 5]
    # - positive branch: [:then, 1, 5, 4, 6, 13] with root_id equal to 0
    # - negative branch: [:else, 2, 8, 4, 9, 18] with root_id equal to 0
    #
    # @param [Hash] given_branches
    #
    # @return [Array]
    #
    def branches_collection(given_branches, root_id = nil)
      @branches_collection ||= []

      given_branches.each do |branch_args, value|
        branch = Branch.new(*branch_args, root_id)

        if value.is_a?(Integer)
          branch.coverage = value
        else
          branches_collection(value, branch.id)
        end

        @branches_collection << branch
      end
      @branches_collection
    end

    #
    # Select the covered branches.
    #
    # @return [Array]
    #
    def covered_branches
      @coverd_branches ||= root_branches.flat_map do |root_branch|
        root_branch.sub_branches(branches).select(&:covered?)
      end
    end

    #
    # Select the missed branches with coverage equal to zero
    #
    # @return [Array]
    #
    def missed_branches
      @missed_branches ||= root_branches.flat_map do |root_branch|
        root_branch.sub_branches(branches).select(&:missed?)
      end
    end

    #
    # Select the perent branches inside the branches hash
    #
    # @return [Array]
    #
    def root_branches
      @root_branches = branches.select(&:root?)
    end

    #
    # Method check if line is branches
    #
    # @param [Integer] line_number
    #
    # @return [Boolean]
    #
    def branchable_line?(line_number)
      branches_report.keys.include?(line_number)
    end

    #
    # Return String with branches message match to the line given
    #
    # @param [Integer] line_number
    #
    # @return [String] ex: "[1, '+'],[2, '-']" two times on negative branch and non on the positive
    #
    def branch_per_line(line_number)
      branches_report[line_number].each_with_object(" ".dup) do |data, message|
        separator = message.strip.empty? ? " " : ", "
        message << (separator + data.to_s)
      end.strip
    end

    #
    # Check if any branches missing on given line number
    #
    # @param [Integer] line_number
    #
    # @return [Boolean]
    #
    def line_with_missed_branch?(line_number)
      return unless branchable_line?(line_number)
      branches_report[line_number].select { |count, _sign| count.zero? }.any?
    end

    #
    # Build full branches report
    # Root branches represent the wrapper of all condition state that
    # have inside the branches
    #
    # @return [Hash]
    #
    def build_branches_report
      root_branches.each_with_object({}) do |root_branch, statistics|
        statistics.merge!(condition_report(root_branch))
      end
    end

    #
    # Create hash as branches coverage report
    # keys: lines numbers matching the branch start line
    # Values: Array with matched branches data
    #
    # @param [Array] branches
    #
    # @return [Hash] ex: {
    #   1 => [[1,"+"], [0, "-"]],
    #   4 => [[10, "+"]]
    # }
    #
    def condition_report(root_branch)
      if root_branch.inline_branch?(branches)
        inline_condition_report(root_branch)
      else
        multiline_condition_report(root_branch)
      end
    end

    #
    # Collect the information from all sub branches reports
    #
    # @param [Branch object] root_branch
    #
    # @return [Hash]
    #
    def multiline_condition_report(root_branch)
      root_branch.sub_branches(branches).each_with_object({}) do |branch, cov_report|
        cov_report[branch.start_line - 1] = [branch.report]
      end
    end

    #
    # Collect all the reports from all branches that are
    # on same line (positive & negative)
    #
    # @param [Branch object] root_branch
    #
    # @return [Hash] ex: { 4 => [[10, "+"], [0, "-"]]}
    #
    #
    def inline_condition_report(root_branch)
      sub_branches = root_branch.sub_branches(branches)
      inline_result = sub_branches.each_with_object([]) do |branch, inline_report|
        inline_report << branch.report
      end
      {root_branch.start_line => inline_result}
    end

  private

    # ruby 1.9 could use Float#round(places) instead
    # @return [Float]
    def round_float(float, places)
      factor = Float(10 * places)
      Float((float * factor).round / factor)
    end
  end
end
