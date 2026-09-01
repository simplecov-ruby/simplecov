# frozen_string_literal: true

require_relative "branches_combiner"
require_relative "lines_combiner"
require_relative "methods_combiner"

module SimpleCov
  module Combine
    #
    # Folds any number of resultsets' coverage into one, absorbing them one
    # at a time so that a caller reading resultsets off disk never holds more
    # than one in memory, and so the accumulated side can be updated in place
    # rather than rebuilt once per resultset.
    #
    class CoverageAccumulator
      # A file some process actually loaded has at least one executed line; a
      # simulated (never-loaded) file's lines are all `nil` or `0`.
      #
      # `Array()` plus the `Numeric` test rather than `any?(&:positive?)`
      # because this reads straight off a parsed resultset, which is external
      # input and can carry anything under "lines".
      def self.executed?(lines)
        counts = Array(lines) #: Array[untyped]
        counts.any? { |count| count.is_a?(Numeric) && count.positive? }
      end

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
        # Whether a criterion is enabled can't change mid-fold, so read it once
        # here rather than once per file. `branch_coverage?` reaches
        # `Coverage.supported?`, and a large parallel run merges thousands of
        # files.
        @branch_coverage = SimpleCov.branch_coverage?
        @method_coverage = SimpleCov.method_coverage?
      end

      def absorb(coverage)
        return self unless coverage

        files = (@files ||= {}) #: Hash[String, untyped]
        coverage.each do |filename, file_coverage|
          files[filename] = merge_file(files[filename], file_coverage)
        end

        self
      end

      # `nil` until the first absorb, so callers can tell "no results" apart
      # from "results that cover nothing": only the former means there is no
      # report to build.
      def result
        @files&.transform_values do |entry|
          case entry
          when MergedFile then entry.to_h
          else entry
          end
        end
      end

      private

      def merge_file(existing, file_coverage)
        case existing
        when nil then file_coverage
        when MergedFile then existing.absorb(file_coverage)
        else MergedFile.new(existing, branches: @branch_coverage, methods: @method_coverage).absorb(file_coverage)
        end
      end

      #
      # One file's accumulated coverage.
      #
      # A criterion is carried for this file when the data carries it, not when
      # this process happens to measure it: `simplecov merge` never ran
      # SimpleCov.start at all, and dropping a table it did not ask for would
      # lose branch data the producers did measure. A nil table means nobody
      # measured that criterion, an empty one means it was measured and the
      # file has none.
      #
      class MergedFile
        def initialize(coverage, branches:, methods:)
          @branch_coverage = branches
          @method_coverage = methods
          @lines = LinesCombiner.merge_into(nil, coverage["lines"])
          branches_table = coverage["branches"]
          @branches = BranchesCombiner.absorb(new_table, branches_table) if branches || branches_table
          @methods = MethodsCombiner.absorb(nil, coverage["methods"])
        end

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
        # and method tuples are authoritative and the other side's are dropped.
        # SimulateCoverage synthesizes those tuples statically, so a location
        # that drifts from what Coverage emits would otherwise be unioned in by
        # position and survive as a phantom, permanently-missed branch (#1233).
        # Lines are never dropped: a simulated file's line shape is correct and
        # carries the unloaded-file denominator (#1059).
        def reconcile_synthesized(coverage)
          incoming_lines = coverage["lines"]
          return absorb_tuples(coverage) unless lines_measured?(@lines) && lines_measured?(incoming_lines)

          incoming_executed = executed?(incoming_lines)

          if executed?(@lines).equal?(incoming_executed)
            absorb_tuples(coverage)
          elsif incoming_executed
            replace_tuples(coverage)
          else
            drop_incoming_tuples(coverage)
          end
        end

        def absorb_tuples(coverage)
          branches_table = coverage["branches"]
          @branches = BranchesCombiner.absorb(@branches || new_table, branches_table) if branches_table
          @methods = MethodsCombiner.absorb(@methods, coverage["methods"])
        end

        def drop_incoming_tuples(coverage)
          @methods ||= {} if @method_coverage && coverage["methods"] #: Hash[untyped, untyped]
        end

        def replace_tuples(coverage)
          @branches = authoritative_table(BranchesCombiner, coverage["branches"], @branch_coverage)
          @methods = authoritative_table(MethodsCombiner, coverage["methods"], @method_coverage && !@methods.nil?)
        end

        def authoritative_table(combiner, table, keep_empty)
          return combiner.absorb(new_table, table) if table

          new_table if keep_empty
        end

        # Absent lines do not mean the side never ran: a branch-only or
        # method-only run omits them even for the files it loaded.
        def lines_measured?(lines)
          !Array(lines).empty?
        end

        def executed?(lines)
          CoverageAccumulator.executed?(lines)
        end
      end
    end
  end
end
