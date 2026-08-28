# frozen_string_literal: true

begin
  require "prism"
rescue LoadError
  # Prism isn't available on this Ruby (older than 3.3 without the gem).
  # `StaticCoverageExtractor.available?` will return false and callers
  # fall back to the previous "empty hashes" behavior.
end

module SimpleCov
  # Static enumeration of the branches and methods Ruby's `Coverage` library
  # WOULD have reported if a file had been loaded with `branches: true` /
  # `methods: true`. Used by `SimulateCoverage` to backfill data for files
  # added via `cover` / `track_files` that were never `require`'d during the
  # run — so unloaded files contribute to the branch/method denominators
  # symmetrically with their line coverage, instead of vanishing from the
  # totals (see #1059).
  #
  # Implementation uses Prism (stdlib in Ruby 3.3+, gem on older Rubies).
  # When Prism isn't available, `available?` returns false and SimulateCoverage
  # falls back to the previous behavior — older Rubies keep working, just
  # without the synthesized data.
  #
  # The emitted shape mirrors `Coverage.result[path]` for the same file:
  # branches are nested as `{condition_tuple => {arm_tuple => 0, ...}}` and
  # methods as `{["ClassName", :name, lines/cols] => 0}`. Position info
  # comes from Prism's reported source locations; it doesn't always match
  # `Coverage`'s byte-for-byte (the two parsers report slightly different
  # column conventions for some constructs), but lines are reliable and
  # downstream consumers that key off line numbers (the HTML formatter,
  # SonarQube, etc.) see the data they expect.
  module StaticCoverageExtractor
    extend self

    # simplecov:disable branch
    # The Prism-unavailable arm of this ternary is unreachable when Prism
    # itself IS loadable, which is every engine that runs the dogfood
    # report. Callers assert on it, and SimulateCoverage's spec exercises
    # the fallback by stubbing this to false.
    #
    def available?
      defined?(Prism) ? true : false
    end
    # simplecov:enable branch

    # Parse `source` (a string of Ruby) and return a hash of the form
    # `{"branches" => {...}, "methods" => {...}}` matching the shape that
    # `Coverage.result[path]` produces. Returns nil on parse failure or
    # when Prism isn't available; callers should treat that as "couldn't
    # extract — fall back to empty hashes."
    def call(source)
      return nil unless available?

      result = Prism.parse(source)
      return nil if result.failure?

      visitor = Visitor.new
      visitor.visit(result.value)
      {"branches" => visitor.branches, "methods" => visitor.methods}
    rescue StandardError
      # simplecov:disable line
      # Parser errors beyond the .failure? check, unsupported AST shapes,
      # or anything else: fall back to empty hashes rather than crashing
      # the whole report. Defensive; hard to trigger from a real source
      # input that Prism accepts at parse time.
      nil
      # simplecov:enable line
    end

    # Summarize a source file's REAL branch and method positions, for the
    # `:eval_generated` filter (SimpleCov.ignore_branches /
    # SimpleCov.ignore_methods, #1046). Returns a hash:
    #
    #   {
    #     branches: Set[start_line, ...],         # e.g., [3, 12, 20]
    #     methods:  Set[[name, start_line], ...]  # e.g., [[:foo, 7], [:bar, 13]]
    #   }
    #
    # Branch matching is start_line-only rather than by the full tuple.
    # Static extraction and Coverage can still disagree on a branch's exact
    # column positions (and, for some constructs, its type), so matching on
    # start_line alone is the conservative choice that tolerates those
    # differences. Coincidental line-sharing between a real branch and an
    # eval-generated one will keep both, which is an acceptable
    # false-negative for an opt-in filter. Method matching uses
    # (name, start_line) since a method name is unique at any line.
    #
    # Returns nil when Prism is unavailable or parsing fails, signaling
    # callers to keep every Coverage entry (no false drops).
    def real_source_positions(source)
      extracted = call(source)
      return nil unless extracted

      {
        branches: extracted.fetch("branches").keys.to_set { |tuple| branch_start_line(*tuple) },
        methods: extracted.fetch("methods").keys.to_set { |tuple| method_identity(*tuple) }
      }
    end

    # Both keys carry their start line third, after the parts that vary
    # between recordings. Read through a parameter list rather than an
    # index, because every spelling of an index answers the same for a
    # tuple of this fixed shape, and so does every spelling of a block's
    # destructuring. Binding an argument has only the one spelling.
    def branch_start_line(_type, _id, start_line, *)
      start_line
    end

    def method_identity(_class_name, name, start_line, *)
      [name, start_line]
    end
  end
end

# simplecov:disable branch
# The `else` arm (Prism missing) is unreachable on engines where the
# dogfood report runs; the Visitor class only matters when Prism is
# loadable.
require_relative "static_coverage_extractor/visitor" if SimpleCov::StaticCoverageExtractor.available?
# simplecov:enable branch
