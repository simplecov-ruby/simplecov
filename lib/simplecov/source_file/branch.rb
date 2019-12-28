# frozen_string_literal: true

module SimpleCov
  class SourceFile
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
