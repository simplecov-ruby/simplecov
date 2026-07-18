# frozen_string_literal: true

module SimpleCov
  module Combine
    #
    # Handle combining two coverage results for same file
    #
    # Should be called through `SimpleCov.combine`.
    module FilesCombiner
    module_function

      empty_table = {} #: Hash[untyped, untyped]
      EMPTY_TABLE = empty_table.freeze
      private_constant :EMPTY_TABLE

      # Branch/method tuples drawn from a simulated (never-loaded) file
      # when the other side of the merge was actually executed.
      NO_SYNTHESIZED = {"branches" => EMPTY_TABLE, "methods" => EMPTY_TABLE}.freeze

      #
      # Combines the results for 2 coverages of a file.
      #
      # @return [Hash]
      #
      def combine(coverage_a, coverage_b)
        source_a, source_b = reconcile_synthesized(coverage_a, coverage_b)

        combination = {"lines" => Combine.combine(LinesCombiner, coverage_a["lines"], coverage_b["lines"])}
        if SimpleCov.branch_coverage?
          combined_branches = Combine.combine(BranchesCombiner, source_a["branches"], source_b["branches"])
          combination["branches"] = combined_branches || {}
        end
        if SimpleCov.method_coverage?
          combination["methods"] = Combine.combine(MethodsCombiner, source_a["methods"], source_b["methods"])
        end
        combination
      end

      # When exactly one side of the merge was actually executed, its branch
      # and method tuples are authoritative and the other side's are dropped.
      # A simulated entry (SimulateCoverage backfills tracked-but-unloaded
      # files) synthesizes those tuples statically, so a location that drifts
      # from what Coverage emits would otherwise be unioned in by position
      # and survive as a phantom, permanently-missed branch (see #1233). This
      # contains any such drift to denominator inflation for files no process
      # loaded, rather than a false miss on a covered file. Lines are never
      # dropped: a simulated file's line shape is correct and carries the
      # unloaded-file denominator (#1059).
      #
      # Returns the two coverages to draw branch/method tuples from, blanking
      # the non-executed side only when the other side was executed. When
      # both sides were executed (two real runs) or neither was (all
      # simulated), both are returned unchanged and combine normally.
      def reconcile_synthesized(coverage_a, coverage_b)
        executed_a = executed?(coverage_a)
        executed_b = executed?(coverage_b)
        return [coverage_a, coverage_b] if executed_a == executed_b

        executed_a ? [coverage_a, NO_SYNTHESIZED] : [NO_SYNTHESIZED, coverage_b]
      end

      # A file some process actually loaded has at least one executed line;
      # a simulated (never-loaded) file's lines are all `nil` or `0`.
      def executed?(coverage)
        lines = Array(coverage["lines"]) #: Array[Integer?]
        lines.any? { |count| count&.positive? }
      end
    end
  end
end
