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
      # `Array()` rather than a bare `any?` because this reads straight off a
      # parsed resultset, which is external input: a file written by another
      # SimpleCov version, or hand-edited, can carry anything under "lines".
      # Coercing keeps a malformed entry to a wrong answer instead of a
      # NoMethodError out of the middle of a merge.
      def self.executed?(lines)
        counts = Array(lines) #: Array[Integer?]
        counts.any? { |count| count&.positive? }
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
        else MergedFile.new(existing).absorb(file_coverage)
        end
      end

      #
      # One file's accumulated coverage, against state this object owns
      # outright rather than rebuilt for each merged pair.
      #
      class MergedFile
        def initialize(coverage)
          # Whether a criterion is enabled can't change mid-merge, so it is
          # read once per file here rather than once per merged pair.
          @branch_coverage = SimpleCov.branch_coverage?
          @method_coverage = SimpleCov.method_coverage?

          @lines = coverage["lines"]&.dup
          # Branch coverage always reports a table, even an empty one, so
          # `SourceFile` can tell "no branches in this file" from "branch
          # coverage was off". Method coverage stays `nil` until some
          # resultset actually carries methods.
          @branches = @branch_coverage ? BranchesCombiner.absorb({}, coverage["branches"]) : nil
          @methods = @method_coverage ? MethodsCombiner.absorb(nil, coverage["methods"]) : nil
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
          merged["branches"] = BranchesCombiner.materialize(@branches) if @branch_coverage
          merged["methods"] = @methods && MethodsCombiner.materialize(@methods) if @method_coverage
          merged
        end

      private

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
          accumulated_executed = executed?(@lines)
          incoming_executed = executed?(coverage["lines"])

          if accumulated_executed == incoming_executed
            absorb_tuples(coverage)
          elsif incoming_executed
            replace_tuples(coverage)
          else
            drop_incoming_tuples
          end
        end

        # Both sides agree on whether they ran: union their tuples.
        def absorb_tuples(coverage)
          BranchesCombiner.absorb(@branches, coverage["branches"]) if @branch_coverage
          @methods = MethodsCombiner.absorb(@methods, coverage["methods"]) if @method_coverage
        end

        # Only the incoming side ran, so what's accumulated is synthesized:
        # start its tuples over from the executed side's.
        def replace_tuples(coverage)
          @branches = BranchesCombiner.absorb({}, coverage["branches"]) if @branch_coverage
          @methods = MethodsCombiner.absorb({}, coverage["methods"]) if @method_coverage
        end

        # Only the accumulated side ran, so the incoming tuples are
        # synthesized and contribute nothing. The empty method table stands in
        # for the blanked side, which is what a pair against `NO_SYNTHESIZED`
        # used to produce for a file that has no methods yet.
        def drop_incoming_tuples
          @methods ||= {} if @method_coverage #: Hash[untyped, untyped]
        end

        def executed?(lines)
          CoverageAccumulator.executed?(lines)
        end
      end
    end
  end
end
