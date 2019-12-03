# frozen_string_literal: true

module SimpleCov
  module Supports
    module BranchSupport
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
      # else branch is always present no matter if we declare it in code or not
      # => Else declared start_line != root_branch_line
      # => Else not declared start_line == root_branch_line
      # for this case we ignore if its not declared becase it's useless
      #
      # @param [Array] branches
      #
      # @return [Array] <description>
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
        return unless root?
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
  end
end
