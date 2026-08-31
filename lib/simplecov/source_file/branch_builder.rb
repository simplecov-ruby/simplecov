# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Builds the `SourceFile::Branch` objects for a source file from the raw
    # branch data Ruby's Coverage library reports, applying the
    # `ignore_branches` filters and marking branches inside disabled chunks as
    # skipped.
    class BranchBuilder
      def initialize(source_file)
        @source_file = source_file
      end

      def call
        coverage_branch_data = @source_file.coverage_data["branches"] || {}
        branches = coverage_branch_data.flat_map do |condition, coverage_branches|
          next [] if eval_generated_condition_to_ignore?(condition)

          build_branches_from(condition, coverage_branches)
        end

        process_skipped(branches)
      end

    private

      # Coverage attributes an eval'd branch to the caller's `__FILE__` /
      # `__LINE__`, so a Rails `delegate :foo, to: :bar` call surfaces inside the
      # source file as if there were branches at the `delegate` line. Prism never
      # sees those branches in the static source, so a condition whose start_line
      # isn't in the real-source branch set must be eval-generated (#1046).
      def eval_generated_condition_to_ignore?(condition)
        return false unless SimpleCov.ignored_branch?(:eval_generated)

        positions = @source_file.real_source_positions
        # simplecov:disable branch — nil branch fires only when Prism is unavailable
        return false unless positions

        # simplecov:enable branch

        _type, _id, start_line, * = RubyDataParser.call(condition)
        !positions.fetch(:branches).include?(start_line)
      end

      def build_branches_from(condition, branches)
        _condition_type, _condition_id, *condition_range = RubyDataParser.call(condition)

        branches.filter_map do |branch_data, hit_count|
          build_branch(RubyDataParser.call(branch_data), hit_count, condition_range)
        end
      end

      # The coverage data hands in `[:then, 4, 6, 6, 6, 10]`, which is
      # [type, id, start_line, start_col, end_line, end_col].
      def build_branch(branch_data, hit_count, condition_range)
        type, _id, start_line, start_col, end_line, end_col = branch_data
        return nil if implicit_else_to_ignore?(type, [start_line, start_col, end_line, end_col], condition_range)

        Branch.new(
          start_line: start_line,
          end_line: end_line,
          coverage: hit_count,
          inline: start_line.eql?(condition_range.first),
          type: type
        )
      end

      # Ruby's Coverage reports a synthetic `:else` for constructs with no literal
      # `else` keyword. The signal is structural: a synthetic else reuses its
      # parent condition's full source range, while an explicit `else` arm carries
      # a narrower one. Comparing the full range rather than just `start_line` is
      # what distinguishes a ternary's explicit else on the condition's own line
      # from a postfix `return if cond` (#1033).
      def implicit_else_to_ignore?(type, branch_range, condition_range)
        return false unless type.equal?(:else)
        return false unless SimpleCov.ignored_branch?(:implicit_else)

        branch_range.eql?(condition_range)
      end

      # A non-inline branch's source range starts on its arm body, but
      # `report_line` is the condition line above it, which is where the user sees
      # the branch and would naturally place an inline disable directive. Honour
      # both.
      def process_skipped(branches)
        chunks = @source_file.skip_chunks_for(:branch)

        # `# simplecov:disable branch` directive. Honour both.
        branches.each do |branch|
          branch.skipped! if chunks.any? { |chunk| branch.overlaps_with?(chunk) || chunk.include?(branch.report_line) }
        end
      end
    end
  end
end
