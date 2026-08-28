# frozen_string_literal: true

require_relative "simulate_coverage"

module SimpleCov
  # Fills in coverage for files that were tracked (via `cover` / `track_files`)
  # but never loaded, so they count toward the denominators instead of being
  # absent from the report entirely.
  #
  # This is the mechanism; the merge-time policy of *when* to inject and
  # which criteria the simulated files carry lives in
  # `ResultMerger::UnloadedFiles` — easy names to confuse.
  #
  # Everything arrives as arguments rather than being read from the SimpleCov
  # singleton. The merge step performs this injection on behalf of the processes
  # that contributed to it, and it does not necessarily share their
  # configuration: a standalone `collate` never ran `SimpleCov.start`, so it has
  # no `cover` glob of its own and takes the tracked paths from the resultsets
  # instead. See #1250.
  module UnloadedFileInjector
    extend self

    # Expand `globs` into absolute paths, relative to `root` rather than
    # `Dir.pwd` — test runners that chdir (or CI scripts that invoke the suite
    # from a subdirectory) would otherwise silently miss files and produce a
    # different set per environment. See #1106.
    # `reject:` are the producing process's path-decidable filters. Paths its
    # own report would exclude must not be recorded as tracked, or a merge that
    # does not share the configuration would simulate them back in. Before
    # injection moved to the merge the producer filtered them out of its own
    # result and they never reached a resultset. A block filter is handed the
    # source file and may consult coverage that does not exist yet, so those
    # still fall to the merging process's filter chain. See #1250.
    def discover(globs, root:, reject: [])
      paths = globs.compact
                   .flat_map { |glob| Dir.glob(glob, base: root) }
                   .uniq
                   .map { |path| File.expand_path(path, root) }
      # With nothing to reject the filter below would keep every path
      # anyway; this saves building a SourceFile per path to find that
      # out.
      return paths if reject.empty?

      paths.reject { |path| rejected?(path, reject) }
    end

    # `SourceFile` reads source and builds lines lazily, so a path-only filter
    # answers without anything here touching disk.
    def rejected?(path, filters)
      candidate = SourceFile.new(path, NO_COVERAGE_YET, loaded: false)
      filters.any? { |filter| filter.matches?(candidate) }
    end

    no_coverage_yet = {"lines" => []} #: Hash[String, Array[untyped]]
    NO_COVERAGE_YET = no_coverage_yet.freeze
    private_constant :NO_COVERAGE_YET

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
