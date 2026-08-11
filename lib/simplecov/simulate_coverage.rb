# frozen_string_literal: true

require "coverage"
require_relative "static_coverage_extractor"

module SimpleCov
  #
  # Responsible for producing file coverage metrics.
  #
  module SimulateCoverage
  module_function

    #
    # Simulate a file coverage report for a file that was tracked but never
    # required. Returns the same hash shape as `Coverage.result` (lines,
    # branches, methods).
    #
    # The line classification comes from `Coverage.line_stub` — the same
    # classification the runtime would have produced if the file had been
    # required — overlaid with SimpleCov's `# :nocov:` toggles and
    # `# simplecov:disable line` directive ranges, which `Coverage` doesn't
    # know about. This keeps "relevant lines" identical whether a file was
    # loaded or just tracked, fixing the multi-line statement discrepancy
    # in https://github.com/simplecov-ruby/simplecov/issues/654.
    #
    # Branches and methods are enumerated by static analysis (via
    # `StaticCoverageExtractor`, which uses Prism). Earlier behavior left
    # both as empty hashes, which made unloaded files invisible to the
    # branch/method denominators while their lines DID count — so a
    # `track_files`/`cover` glob that picked up files without specs
    # silently inflated branch% relative to line%. See
    # https://github.com/simplecov-ruby/simplecov/issues/1059. When the
    # file can't be parsed, fall back to the old empty hashes — old
    # behavior, old tradeoff.
    #
    # Pass `synthesize: false` to skip the static analysis and return the
    # empty hashes directly. Callers use it when neither branch nor method
    # coverage is enabled, since nothing will read the tuples and the Prism
    # parse is about half the cost of simulating a file. See #1250.
    #
    # Pass `lines: false` to omit the `"lines"` key entirely, mirroring what
    # `Coverage.result` reports for a file loaded under a branch-only or
    # method-only run. Emitting zeroed lines there would make a simulated
    # file indistinguishable from one a sibling process actually loaded once
    # the two are merged.
    #
    # @return [Hash]
    #
    def call(absolute_path, synthesize: true, lines: true)
      source_lines = read_lines(absolute_path)
      simulated = synthesized_tuples(source_lines, synthesize)
      return simulated unless lines

      classified = coverage_stub(absolute_path, source_lines) ||
                   LinesClassifier.new.classify(source_lines)
      {"lines" => classified}.merge(simulated)
    end

    # The branch and method tuples for a file, or empty hashes when the static
    # analysis is skipped (nothing enabled reads them) or the file doesn't
    # parse.
    def synthesized_tuples(source_lines, synthesize)
      empty = {"branches" => {}, "methods" => {}} #: Hash[String, Hash[untyped, untyped]]
      synthesized = (StaticCoverageExtractor.call(source_lines.join) if synthesize) || empty

      {"branches" => synthesized["branches"], "methods" => synthesized["methods"]}
    end

    # SystemCallError, not just ENOENT: a `track_files` glob can sweep
    # up an unreadable file or a directory named like a Ruby file
    # (EACCES, EISDIR), and simulation must degrade to "empty file"
    # rather than crash the merge or report step.
    def read_lines(path)
      File.readlines(path)
    rescue SystemCallError
      []
    end

    # Combine `Coverage.line_stub` (which gets multi-line statements right)
    # with `LinesClassifier` (which knows about `# :nocov:` toggles and
    # `# simplecov:disable line` ranges). Returns nil — and the caller
    # falls back to `LinesClassifier` alone — when `Coverage` can't read
    # or parse the file.
    def coverage_stub(path, source_lines)
      stub = Coverage.line_stub(path)
      classifier_output = LinesClassifier.new.classify(source_lines)
      stub.each_index { |idx| stub[idx] = nil if classifier_output[idx].nil? }
      stub
    rescue SystemCallError, SyntaxError
      # SystemCallError for the same reason as read_lines above:
      # line_stub reads the file itself, so EACCES/EISDIR surface here
      # too.
      nil
    end
  end
end
