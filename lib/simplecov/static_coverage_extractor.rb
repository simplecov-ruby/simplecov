# frozen_string_literal: true

begin
  require "prism"
rescue LoadError
  # Prism isn't available on this Ruby (older than 3.3 without the gem).
  # `StaticCoverageExtractor.available?` will return false and callers fall
  # back to the previous "empty hashes" behavior.
end

module SimpleCov
  # Static enumeration of the branches and methods Ruby's `Coverage` library
  # would have reported if a file had been loaded with `branches: true` /
  # `methods: true`. Used by `SimulateCoverage` to backfill data for files
  # added via `cover` / `track_files` that were never required during the run,
  # so unloaded files contribute to the branch/method denominators
  # symmetrically with their line coverage (#1059).
  #
  # The emitted shape mirrors `Coverage.result[path]` for the same file.
  # Position info comes from Prism's reported source locations; it doesn't
  # always match `Coverage`'s byte-for-byte, but lines are reliable and
  # downstream consumers that key off line numbers see the data they expect.
  module StaticCoverageExtractor
    extend self

    def available?
      defined?(Prism) ? true : false
    end

    # Parse `source` and return `{"branches" => {...}, "methods" => {...}}`
    # matching the shape `Coverage.result[path]` produces. Returns nil on parse
    # failure or when Prism isn't available, which callers treat as "couldn't
    # extract, fall back to empty hashes".
    def call(source)
      return nil unless available?

      result = Prism.parse(source)
      return nil if result.failure?

      visitor = Visitor.new
      visitor.visit(result.value)
      {"branches" => visitor.branches, "methods" => visitor.methods}
    rescue StandardError
      # Parser errors beyond the .failure? check, unsupported AST shapes, or
      # anything else: fall back to empty hashes rather than crashing the whole
      # report.
      nil
    end

    # Summarize a source file's real branch and method positions, for the
    # `:eval_generated` filter (#1046). Answers:
    #
    #   {
    #     branches: Set[start_line, ...],         # e.g., [3, 12, 20]
    #     methods:  Set[[name, start_line], ...]  # e.g., [[:foo, 7], [:bar, 13]]
    #   }
    #
    # Branch matching is start_line-only rather than by the full tuple. Static
    # extraction and Coverage can still disagree on a branch's exact column
    # positions, so matching on start_line alone tolerates those differences.
    # Coincidental line-sharing between a real branch and an eval-generated one
    # keeps both, an acceptable false-negative for an opt-in filter.
    #
    # Returns nil when Prism is unavailable or parsing fails, signaling callers
    # to keep every Coverage entry.
    def real_source_positions(source)
      extracted = call(source)
      return nil unless extracted

      {
        branches: extracted.fetch("branches").keys.to_set { |tuple| branch_start_line(*tuple) },
        methods: extracted.fetch("methods").keys.to_set { |tuple| method_identity(*tuple) }
      }
    end

    # Both keys carry their start line third, after the parts that vary between
    # recordings. Read through a parameter list rather than an index, because
    # every spelling of an index answers the same for a tuple of this fixed
    # shape. Binding an argument has only the one spelling.
    def branch_start_line(_type, _id, start_line, *)
      start_line
    end

    def method_identity(_class_name, name, start_line, *)
      [name, start_line]
    end
  end
end

# simplecov:disable branch
# The `else` arm (Prism missing) is unreachable on engines where the dogfood
# report runs; the Visitor class only matters when Prism is loadable.
require_relative "static_coverage_extractor/visitor" if SimpleCov::StaticCoverageExtractor.available?
# simplecov:enable branch
