# frozen_string_literal: true

require_relative "simulate_coverage"

module SimpleCov
  # Fills in coverage for files that were tracked (via `cover` / `track_files`)
  # but never loaded, so they count toward the denominators instead of being
  # absent from the report entirely.
  #
  # Everything arrives as arguments rather than being read from the SimpleCov
  # singleton. The merge step performs this injection on behalf of the processes
  # that contributed to it, and it does not necessarily share their
  # configuration: a standalone `collate` never ran `SimpleCov.start`, so it has
  # no `cover` glob of its own and takes the tracked paths from the resultsets
  # instead. See #1250.
  module UnloadedFileInjector
  module_function

    # Expand `globs` into absolute paths, relative to `root` rather than
    # `Dir.pwd` — test runners that chdir (or CI scripts that invoke the suite
    # from a subdirectory) would otherwise silently miss files and produce a
    # different set per environment. See #1106.
    def discover(globs, root:)
      globs.compact
           .flat_map { |glob| Dir.glob(glob, base: root) }
           .uniq
           .map { |path| File.expand_path(path, root) }
    end

    # Add simulated coverage for every path `coverage` does not already carry.
    # Paths that are present are left alone, whoever put them there, which is
    # what lets this run over resultsets a previous SimpleCov already injected
    # into without double-counting or overwriting real data.
    #
    # Returns the augmented coverage and the set of paths that were added.
    def call(coverage, paths, synthesize:, lines:)
      injected = Set.new
      augmented = coverage.dup

      paths.each do |path|
        next if augmented.key?(path)

        augmented[path] = SimulateCoverage.call(path, synthesize: synthesize, lines: lines)
        injected << path
      end

      [augmented, injected]
    end
  end
end
