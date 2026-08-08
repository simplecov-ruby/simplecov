# frozen_string_literal: true

require_relative "branches_combiner"
require_relative "lines_combiner"
require_relative "methods_combiner"

module SimpleCov
  module Combine
    #
    # Folds any number of resultsets' coverage into one, absorbing them one
    # at a time.
    #
    # This replaces a pairwise `reduce` over the resultsets, which rebuilt
    # the entire accumulated structure on every one of its N-1 steps: a
    # fresh outer file hash, a fresh lines array for every file, and a fresh
    # branch / method table for every file whose keys were re-interned from
    # their tuples each time. On a 160-worker run over ~1,800 files that is
    # ~290,000 whole-file rebuilds to produce ~1,800 files of output.
    #
    # The accumulated side is private to the fold, so it can be updated in
    # place instead, and the interned tables only have to be turned back into
    # tuple-keyed hashes once, at the end.
    #
    # Resultsets are absorbed one at a time rather than taken as a list, so
    # `ResultMerger.merge_results` can keep reading and discarding them one
    # file at a time — reading 100s of CI jobs' worth of coverage into memory
    # at once is what that method is careful not to do.
    #
    class CoverageAccumulator
      # A file some process actually loaded has at least one executed line;
      # a simulated (never-loaded) file's lines are all `nil` or `0`. This is
      # the signal the merge reconciles synthesized tuples on, and the one
      # `ResultMerger` re-derives a merged result's not-loaded set from, so it
      # lives here rather than being spelled out at each site.
      #
      # `Array()` plus the `Numeric` test rather than a bare
      # `any?(&:positive?)` because this reads straight off a parsed
      # resultset, which is external input: a file written by another
      # SimpleCov version, or hand-edited, can carry anything under
      # "lines" — a Hash coerces to pairs, a String to itself. Keeping a
      # malformed entry to a wrong answer instead of a NoMethodError out
      # of the middle of a merge is the point.
      def self.executed?(lines)
        counts = Array(lines) #: Array[untyped]
        counts.any? { |count| count.is_a?(Numeric) && count.positive? }
      end

      #
      # Folds `[command_names, coverage]` pairs into one merged coverage.
      #
      # `pairs` is only ever iterated, so a caller that reads resultsets off
      # disk can hand in a lazy enumerable and never hold more than one in
      # memory — which is what `ResultMerger.merge_results` is careful about.
      #
      # @return [Array] the concatenated command names and the merged coverage
      #
      def self.fold(pairs)
        accumulator = new
        command_names = [] #: Array[String]

        pairs.each do |names, coverage|
          command_names.concat(names)
          accumulator.absorb(coverage)
        end

        [command_names, accumulator.result]
      end

      def initialize
        @files = {} #: Hash[String, untyped]
        @absorbed = false
        # Whether a criterion is enabled can't change mid-fold, so read it once
        # here rather than once per file. `branch_coverage?` reaches
        # `Coverage.supported?`, and a large parallel run merges thousands of
        # files.
        @branch_coverage = SimpleCov.branch_coverage?
        @method_coverage = SimpleCov.method_coverage?
      end

      #
      # Folds one resultset's coverage (filename => per-file coverage) into
      # the accumulator. A `nil` coverage is ignored — a resultset that
      # carried nothing contributes nothing.
      #
      # @return [CoverageAccumulator] self, so absorbs can be chained
      #
      def absorb(coverage)
        return self unless coverage

        @absorbed = true
        coverage.each do |filename, file_coverage|
          @files[filename] = merge_file(@files[filename], file_coverage)
        end

        self
      end

      #
      # The merged coverage, or `nil` when nothing was absorbed at all — the
      # caller needs to tell "no results" apart from "results that cover
      # nothing", and only the former means there is no report to build.
      #
      # A file only one resultset carried is returned exactly as it came in,
      # untouched: with nothing to merge it into, copying it would only cost
      # memory.
      #
      # @return [Hash, nil]
      #
      def result
        return nil unless @absorbed

        @files.transform_values do |entry|
          entry.is_a?(MergedFile) ? entry.to_h : entry
        end
      end

    private

      # The first sighting of a file is kept as-is; the second promotes it to
      # a `MergedFile` that owns its state, and every later one folds into
      # that same object.
      def merge_file(existing, file_coverage)
        case existing
        when nil then file_coverage
        when MergedFile then existing.absorb(file_coverage)
        else MergedFile.new(existing, branches: @branch_coverage, methods: @method_coverage).absorb(file_coverage)
        end
      end

      #
      # One file's accumulated coverage, against state this object owns
      # outright rather than rebuilt for each merged pair.
      #
      class MergedFile
        # A criterion is carried for this file when the data carries it, not
        # when this process happens to measure it. A merge runs on behalf of
        # the processes that produced the resultsets and does not necessarily
        # share their configuration: `simplecov merge` never ran SimpleCov.start
        # at all, and dropping a table it did not ask for would lose branch data
        # the producers did measure. A nil table means nobody measured that
        # criterion; an empty one means it was measured and the file has none.
        def initialize(coverage, branches:, methods:)
          @branch_coverage = branches
          @method_coverage = methods
          @lines = coverage["lines"]&.dup
          # Branch coverage always reports a table, even an empty one, so
          # `SourceFile` can tell "no branches in this file" from "branch
          # coverage was off". Method coverage stays `nil` until some resultset
          # actually carries methods.
          @branches = BranchesCombiner.absorb({}, coverage["branches"]) if branches || coverage["branches"]
          @methods = MethodsCombiner.absorb(nil, coverage["methods"]) if methods || coverage["methods"]
        end

        #
        # Folds one more resultset's coverage for this file in.
        #
        # @return [MergedFile] self
        #
        def absorb(coverage)
          reconcile_synthesized(coverage)
          @lines = LinesCombiner.merge_into(@lines, coverage["lines"])
          self
        end

        def to_h
          merged = {"lines" => @lines} #: Hash[String, untyped]
          merged["branches"] = BranchesCombiner.materialize(@branches) if @branches
          merged["methods"] = MethodsCombiner.materialize(@methods) if @methods
          merged
        end

      private

        def new_table
          {} #: Hash[untyped, untyped]
        end

        # When exactly one side of the merge was actually executed, its branch
        # and method tuples are authoritative and the other side's are
        # dropped. A simulated entry (SimulateCoverage backfills
        # tracked-but-unloaded files) synthesizes those tuples statically, so
        # a location that drifts from what Coverage emits would otherwise be
        # unioned in by position and survive as a phantom, permanently-missed
        # branch (see #1233). This contains any such drift to denominator
        # inflation for files no process loaded, rather than a false miss on a
        # covered file. Lines are never dropped: a simulated file's line shape
        # is correct and carries the unloaded-file denominator (#1059).
        #
        # The accumulated side's executed-ness is re-read on every absorb
        # because folding in an executed resultset can flip it, exactly as it
        # would have flipped between two steps of the pairwise fold.
        def reconcile_synthesized(coverage)
          return absorb_tuples(coverage) unless judgeable?(@lines) && judgeable?(coverage["lines"])

          accumulated_executed = executed?(@lines)
          incoming_executed = executed?(coverage["lines"])

          if accumulated_executed == incoming_executed
            absorb_tuples(coverage)
          elsif incoming_executed
            replace_tuples(coverage)
          else
            drop_incoming_tuples(coverage)
          end
        end

        # Both sides agree on whether they ran: union their tuples. A criterion
        # only the incoming side carries comes into play here, because its
        # tuples survive. It deliberately does not come into play on the path
        # that drops them: promoting there would advertise an empty table
        # sourced from data this merge just discarded, which claims the file
        # has no branches when what is true is that nobody measured them.
        def absorb_tuples(coverage)
          @branches = BranchesCombiner.absorb(@branches || new_table, coverage["branches"]) if
            @branches || coverage["branches"]
          @methods = MethodsCombiner.absorb(@methods, coverage["methods"]) if @methods || coverage["methods"]
        end

        # Only the accumulated side ran, so the incoming tuples are synthesized
        # and contribute nothing. When the discarded side carried a methods
        # table, a measuring process still gets one — the empty table stands in
        # for the blanked side, which is what a pair against a blank one used
        # to produce for a file that has no methods yet. When no side has
        # carried methods at all, the table stays nil (the rule `initialize`
        # documents), the same answer the union path gives.
        def drop_incoming_tuples(coverage)
          @methods ||= {} if @method_coverage && coverage["methods"] #: Hash[untyped, untyped]
        end

        # Only the incoming side ran, so what's accumulated is synthesized:
        # start its tuples over from the executed side's. The authoritative
        # side decides which criteria the file carries, not just their tuples.
        # Keeping a table in play that only the dropped side carried would make
        # the answer depend on which side was seen first.
        def replace_tuples(coverage)
          @branches = authoritative_table(BranchesCombiner, coverage["branches"], @branch_coverage)
          # Methods stay nil until some resultset carries them (see
          # `initialize`), so a measuring process keeps an empty table only
          # when one did.
          @methods = authoritative_table(MethodsCombiner, coverage["methods"], @method_coverage && !@methods.nil?)
        end

        # The executed side's tuples when it has them. Otherwise `keep_empty`
        # decides whether the criterion survives as an empty table, which is
        # what keeps `SourceFile` able to tell "no branches here" from
        # "branches were not measured".
        def authoritative_table(combiner, table, keep_empty)
          return combiner.absorb(new_table, table) if table

          keep_empty ? new_table : nil
        end

        # Whether a side can be judged at all. Absent lines do not mean the side
        # never ran: a branch-only or method-only run omits them even for the
        # files it loaded, so treating that as synthesized would discard real
        # tuples. Unknown means union, which is already what happens when
        # neither side carries lines.
        def judgeable?(lines)
          !Array(lines).empty?
        end

        def executed?(lines)
          CoverageAccumulator.executed?(lines)
        end
      end
    end
  end
end
