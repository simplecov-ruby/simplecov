# frozen_string_literal: true

module SimpleCov
  module Supports
    module SourceFileSupport
      ###
      ## Related to source file lines statistics
      ###

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

      ## Related to source file branches statistics

      #
      # Call recursive method that transform our static hash to array of objects
      # @return [Array]
      #
      def build_branches
        branches_collection(coverage[:branches] || {})
      end

      #
      # Recursive method brings all of the branches as array of objects
      # In logic here we collect only the positive or negative branch,
      # not the first called branch for it
      #
      # @param [Hash] given_branches
      #
      # @return [Array]
      #
      def branches_collection(given_branches, root_id = nil)
        @branches_collection ||= []
        given_branches.each do |branch_args, value|
          branch_args << root_id
          branch = SourceFile::Branch.new(*branch_args)

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
      # Select the covered branches
      # Here we user tree schema because some conditions like case may have additional
      # else that is not in declared inside the code but given by default by coverage report
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
    end
  end
end
