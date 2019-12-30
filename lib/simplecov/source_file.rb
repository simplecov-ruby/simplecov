# frozen_string_literal: true

module SimpleCov
  #
  # Representation of a source file including it's coverage data, source code,
  # source lines and featuring helpers to interpret that data.
  #
  class SourceFile
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

    def build_lines
      coverage_exceeding_source_warn if coverage[:lines].size > src.size
      lines = src.map.with_index(1) do |src, i|
        SimpleCov::SourceFile::Line.new(src, i, coverage[:lines][i - 1])
      end
      process_skipped_lines(lines)
    end

    # no_cov_chunks is zero indexed to work directly with the array holding the lines
    def no_cov_chunks
      @no_cov_chunks ||= build_no_cov_chunks
    end

    def build_no_cov_chunks
      no_cov_lines = src.map.with_index.select { |line, _index| LinesClassifier.no_cov_line?(line) }

      warn "uneven number of nocov comments detected" if no_cov_lines.size.odd?

      @no_cov_chunks =
        no_cov_lines.each_cons(2).map do |(_line_start, index_start), (_line_end, index_end)|
          index_start..index_end
        end
    end

    def process_skipped_lines(lines)
      no_cov_chunks.each { |chunk| lines[chunk].each(&:skipped!) }

      lines
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

    #
    # Return all the branches inside current source file
    def branches
      @branches ||= build_branches
    end

    def no_branches?
      total_branches.empty?
    end

    def branches_coverage_percent
      return 100.0 if no_branches?
      return 0.0 if covered_branches.empty?

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

    ## Related to source file branches statistics

    #
    # Call recursive method that transform our static hash to array of objects
    # @return [Array]
    #
    def build_branches
      coverage_branch_data = coverage.fetch(:branches, {})
      branches = coverage_branch_data.flat_map do |condition, coverage_branches|
        build_branches_from(condition, coverage_branches)
      end

      process_skipped_branches(branches)
    end

    def process_skipped_branches(branches)
      return branches if no_cov_chunks.empty?

      branches.each do |branch|
        branch.skipped! if no_cov_chunks.any? { |no_cov_chunk| branch.overlaps_with?(no_cov_chunk) }
      end

      branches
    end

    # Since we are dumping to and loading from JSON, and we have arrays as keys those
    # don't make their way back to us intact e.g. just as a string or a symbol (currently keys are symbolized).
    #
    # We should probably do something different here, but as it stands these are
    # our data structures that we write so eval isn't _too_ bad.
    #
    # See #801
    #
    def restore_ruby_data_structure(structure)
      # Tests use the real data structures (except for integration tests) so no need to
      # put them through here.
      return structure if structure.is_a?(Array)

      # as of right now the keys are still symbolized
      # rubocop:disable Security/Eval
      eval structure.to_s
      # rubocop:enable Security/Eval
    end

    def build_branches_from(condition, branches)
      # the format handed in from the coverage data is like this:
      #
      #     [:then, 4, 6, 6, 6, 10]
      #
      # which is [type, id, start_line, start_col, end_line, end_col]
      condition_type, condition_id, condition_start_line, * = restore_ruby_data_structure(condition)

      branches
        .map { |branch_data, hit_count| [restore_ruby_data_structure(branch_data), hit_count] }
        .reject { |branch_data, _hit_count| ignore_branch?(branch_data, condition_type, condition_start_line) }
        .map { |branch_data, hit_count| build_branch(branch_data, hit_count, condition_start_line, condition_id) }
    end

    def build_branch(branch_data, hit_count, condition_start_line, condition_id)
      type, id, start_line, _start_col, end_line, _end_col = branch_data

      SourceFile::Branch.new(
        # rubocop these are keyword args please let me keep them, thank you
        # rubocop:disable Style/HashSyntax
        start_line: start_line,
        end_line:   end_line,
        coverage:   hit_count,
        inline:     start_line == condition_start_line,
        positive:   positive_branch?(condition_id, id, type)
        # rubocop:enable Style/HashSyntax
      )
    end

    def ignore_branch?(branch_data, condition_type, condition_start_line)
      branch_type = branch_data[0]
      branch_start_line = branch_data[2]

      # branch coverage always reports case to be with an else branch even when
      # there is no else branch to be covered, it's noticable by the reported start
      # line being the same as that of the condition/case
      condition_type == :case &&
        branch_type == :else &&
        condition_start_line == branch_start_line
    end

    #
    # Branch is positive or negative.
    # For `case` conditions, `when` always supposed as positive branch.
    # For `if, else` conditions:
    # coverage returns matrices ex: [:if, 0,..] => {[:then, 1,..], [:else, 2,..]},
    # positive branch always has id equals to condition id incremented by 1.
    #
    # @return [Boolean]
    #
    def positive_branch?(condition_id, branch_id, branch_type)
      return true if branch_type == :when

      branch_id == (1 + condition_id)
    end

    #
    # Select the covered branches
    # Here we user tree schema because some conditions like case may have additional
    # else that is not in declared inside the code but given by default by coverage report
    #
    # @return [Array]
    #
    def covered_branches
      @covered_branches ||= branches.select(&:covered?)
    end

    #
    # Select the missed branches with coverage equal to zero
    #
    # @return [Array]
    #
    def missed_branches
      @missed_branches ||= branches.select(&:missed?)
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
      branches_report.fetch(line_number, []).each_with_object(+" ") do |data, message|
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
      branches.reject(&:skipped?).each_with_object({}) do |branch, coverage_statistics|
        coverage_statistics[branch.report_line] ||= []
        coverage_statistics[branch.report_line] << branch.report
      end
    end
  end
end
