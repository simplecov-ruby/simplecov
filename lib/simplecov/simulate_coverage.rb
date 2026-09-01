# frozen_string_literal: true

require "coverage"
require_relative "static_coverage_extractor"

module SimpleCov
  module SimulateCoverage
    extend self

    #
    # Simulate a file coverage report for a file that was tracked but never
    # required, in the same hash shape as `Coverage.result`.
    #
    # The line classification comes from `Coverage.line_stub`, the same
    # classification the runtime would have produced if the file had been
    # required, overlaid with SimpleCov's `# :nocov:` toggles and
    # `# simplecov:disable line` directive ranges, which `Coverage` doesn't
    # know about. This keeps "relevant lines" identical whether a file was
    # loaded or just tracked (#654).
    #
    # Branches and methods are enumerated by static analysis. Earlier behavior
    # left both as empty hashes, which made unloaded files invisible to the
    # branch/method denominators while their lines did count, so a glob that
    # picked up files without specs silently inflated branch% relative to
    # line% (#1059). When Prism isn't loadable or the file can't be parsed,
    # fall back to the old empty hashes.
    #
    # Pass `synthesize: false` to skip the static analysis. Callers use it when
    # neither branch nor method coverage is enabled, since nothing will read
    # the tuples and the Prism parse is about half the cost of simulating a
    # file (#1250).
    #
    # Pass `lines: false` to omit the `"lines"` key entirely, mirroring what
    # `Coverage.result` reports for a file loaded under a branch-only or
    # method-only run. Emitting zeroed lines there would make a simulated file
    # indistinguishable from one a sibling process actually loaded.
    #
    def call(absolute_path, synthesize: true, lines: true)
      source_lines = read_lines(absolute_path)
      simulated = synthesized_tuples(source_lines, synthesize)
      return simulated unless lines

      classified = coverage_stub(absolute_path, source_lines) ||
        LinesClassifier.new.classify(source_lines)
      {"lines" => classified}.merge(simulated)
    end

    # Empty hashes when the static analysis is skipped (nothing enabled reads
    # them) or unavailable (no Prism, or the file doesn't parse).
    def synthesized_tuples(source_lines, synthesize)
      empty = {"branches" => {}, "methods" => {}} #: Hash[String, Hash[untyped, untyped]]
      synthesized = (StaticCoverageExtractor.call(source_lines.join) if synthesize) || empty

      {"branches" => synthesized.fetch("branches"), "methods" => synthesized.fetch("methods")}
    end

    # SystemCallError, not just ENOENT: a `track_files` glob can sweep up an
    # unreadable file or a directory named like a Ruby file, and simulation must
    # degrade to "empty file" rather than crash the merge or report step.
    def read_lines(path)
      File.readlines(path)
    rescue SystemCallError
      []
    end

    # Combines `Coverage.line_stub` (which gets multi-line statements right)
    # with `LinesClassifier` (which knows about `# :nocov:` toggles and
    # `# simplecov:disable line` ranges). Answers nil when `Coverage` can't
    # read or parse the file, or the runtime doesn't expose `line_stub`.
    def coverage_stub(path, source_lines)
      return nil unless Coverage.respond_to?(:line_stub)

      # Paired off rather than indexed: the two lists describe the same file
      # line for line. A line the classifier has no verdict for keeps the nil
      # it would have been set to.
      relevance = LinesClassifier.new.classify(source_lines)
      Coverage.line_stub(path).zip(relevance).map { |hits, relevant| hits if relevant }
    rescue SystemCallError, SyntaxError
      # SystemCallError for the same reason as read_lines: line_stub reads the
      # file itself, so EACCES/EISDIR surface here too.
      nil
    end
  end
end
