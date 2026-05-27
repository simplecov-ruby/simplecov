# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Builds the `SourceFile::Branch` objects for a source file from
    # the raw branch data Ruby's Coverage library reports. Applies the
    # `ignore_branches :eval_generated` / `:implicit_else` filters and
    # marks branches inside `# simplecov:disable` / `# :nocov:` chunks
    # as skipped.
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

      # Detect a Coverage-reported branch condition that originates from
      # `eval`/`module_eval`/`class_eval`/`instance_eval` rather than from
      # the file's literal source. Coverage attributes such branches to the
      # caller's `__FILE__`/`__LINE__`, so a Rails `delegate :foo, to: :bar`
      # call surfaces inside the source file as if there were branches at
      # the `delegate` line. Prism never sees those branches in the static
      # source, so a condition whose start_line isn't in the real-source
      # branch set must be eval-generated. Only consulted when the user has
      # opted in via `SimpleCov.ignore_branches :eval_generated`. See #1046.
      def eval_generated_condition_to_ignore?(condition)
        return false unless SimpleCov.ignored_branch?(:eval_generated)

        positions = @source_file.real_source_positions
        # simplecov:disable branch — nil branch fires only when Prism is unavailable
        return false unless positions

        # simplecov:enable branch

        _type, _id, start_line, * = RubyDataParser.call(condition)
        !positions[:branches].include?(start_line)
      end

      def build_branches_from(condition, branches)
        # the format handed in from the coverage data is like this:
        #
        #     [:then, 4, 6, 6, 6, 10]
        #
        # which is [type, id, start_line, start_col, end_line, end_col]
        _condition_type, _condition_id, *condition_range = RubyDataParser.call(condition)

        branches.filter_map do |branch_data, hit_count|
          build_branch(RubyDataParser.call(branch_data), hit_count, condition_range)
        end
      end

      def build_branch(branch_data, hit_count, condition_range)
        type, _id, start_line, start_col, end_line, end_col = branch_data
        return nil if implicit_else_to_ignore?(type, [start_line, start_col, end_line, end_col], condition_range)

        SourceFile::Branch.new(
          start_line: start_line,
          end_line: end_line,
          coverage: hit_count,
          inline: start_line == condition_range.first,
          type: type
        )
      end

      # Detect synthetic `:else` branches that Ruby's Coverage library reports
      # for constructs with no literal `else` keyword in source (`case/in` /
      # `case/when` without else, `||=`, `&&=`, `if`/`unless` without else,
      # and the postfix `return if cond` shape). The signal is structural:
      # a synthetic else reuses its parent condition's *full source range*
      # (start_line, start_col, end_line, end_col all identical), while an
      # explicit `else` arm carries a narrower range — its own keyword/body
      # position rather than the whole conditional. Comparing the full range
      # (not just `start_line`) is what distinguishes a ternary's explicit
      # else on the same line as the condition — `arg == 42 ? :yes : :no`,
      # where the else's columns differ from the parent's — from a postfix
      # `return if cond` where the synthetic else inherits the full range.
      # Only consulted when the user has opted in via
      # `SimpleCov.ignore_branches :implicit_else`. See #1033.
      def implicit_else_to_ignore?(type, branch_range, condition_range)
        return false unless type == :else
        return false unless SimpleCov.ignored_branch?(:implicit_else)

        branch_range == condition_range
      end

      def process_skipped(branches)
        chunks = @source_file.skip_chunks_for(:branch)
        return branches if chunks.empty?

        # A non-inline branch's source range starts on its arm body (e.g. the
        # `:yes` line of `if cond / :yes / else / :no / end`), but `report_line`
        # is the condition line above it — that's where the user sees the
        # branch in the report and where they would naturally place an inline
        # `# simplecov:disable branch` directive. Honour both.
        branches.each do |branch|
          branch.skipped! if chunks.any? { |chunk| branch.overlaps_with?(chunk) || chunk.include?(branch.report_line) }
        end

        branches
      end
    end
  end
end
