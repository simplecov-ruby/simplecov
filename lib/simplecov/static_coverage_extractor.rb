# frozen_string_literal: true

require "set"

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
  module_function

    # simplecov:disable branch
    # The Prism-unavailable arm of this ternary is unreachable when Prism
    # itself IS loadable — i.e., on every engine that exercises the dogfood
    # report. Asserted-on by callers; tested indirectly via the
    # `available?`-returns-false fallback path in SimulateCoverage's spec.
    def available?
      defined?(::Prism) ? true : false
    end
    # simplecov:enable branch

    # Parse `source` (a string of Ruby) and return a hash of the form
    # `{"branches" => {...}, "methods" => {...}}` matching the shape that
    # `Coverage.result[path]` produces. Returns nil on parse failure or
    # when Prism isn't available; callers should treat that as "couldn't
    # extract — fall back to empty hashes."
    def call(source)
      # simplecov:disable branch — `then` arm unreachable when Prism IS loadable
      return nil unless available?

      # simplecov:enable branch

      result = ::Prism.parse(source)
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
    # Branch matching is start_line-only because Coverage's condition type
    # vocabulary (`:if`, `:unless`, `:case`, `:while`, `:until`) does not
    # always match Prism's emitted type (the existing visitor reports
    # `:if` for `unless` and ternary). Coincidental line-sharing between
    # a real branch and an eval-generated one will keep both, which is
    # an acceptable false-negative for an opt-in filter. Method matching
    # uses (name, start_line) since a method name is unique at any line.
    #
    # Returns nil when Prism is unavailable or parsing fails, signaling
    # callers to keep every Coverage entry (no false drops).
    def real_source_positions(source)
      extracted = call(source)
      return nil unless extracted

      {
        branches: extracted["branches"].keys.to_set { |tuple| tuple[2] },
        methods: extracted["methods"].keys.to_set { |tuple| [tuple[1], tuple[2]] }
      }
    end
  end
end

# simplecov:disable branch
# The `else` arm (Prism missing) is unreachable on engines where the
# dogfood report runs; the Visitor class only matters when Prism is
# loadable.
require_relative "static_coverage_extractor/visitor" if SimpleCov::StaticCoverageExtractor.available?
# simplecov:enable branch
