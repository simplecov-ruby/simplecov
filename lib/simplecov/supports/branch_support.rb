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

      # TODO: Refactoring candidate.
      # Return boolean value depends on branches start_line & end_line
      # including single branch conditions & nested branches, ex:
      #   unless/if cond
      #      puts "x"
      #   end
      #   if cond
      #    ..
      #   elsif cond
      #    ..
      #   else
      #    ..
      #   end
      #
      # @return [Boolean]
      #
      def inline_branch?(branches)
        # nested conditions
        return true if branches.any? { |b| b.root_id != id && sub_branches(branches).map(&:start_line).include?(b.start_line) }
        # inline or single branch conditions
        sub_branches(branches).all? { |branch| branch.start_line.eql?(start_line) && branch.end_line.eql?(end_line) }
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
