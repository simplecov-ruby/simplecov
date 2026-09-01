# frozen_string_literal: true

require_relative "simulate_coverage"

module SimpleCov
  # Fills in coverage for files that were tracked but never loaded, so they
  # count toward the denominators instead of being absent from the report.
  # This is the mechanism; the merge-time policy of when to inject lives in
  # `ResultMerger::UnloadedFiles`.
  #
  # Everything arrives as arguments rather than being read from the SimpleCov
  # singleton, because the merge performs this injection on behalf of
  # processes whose configuration it does not necessarily share (#1250).
  module UnloadedFileInjector
    extend self

    # Globs expand relative to `root` rather than `Dir.pwd`: runners that chdir
    # would otherwise silently miss files and produce a different set per
    # environment (#1106).
    #
    # `reject:` are the producing process's path-decidable filters. Paths its
    # own report would exclude must not be recorded as tracked, or a merge that
    # does not share the configuration would simulate them back in. A block
    # filter is handed the source file and may consult coverage that does not
    # exist yet, so those still fall to the merging process's filter chain.
    def discover(globs, root:, reject: [])
      paths = globs.compact
        .flat_map { |glob| Dir.glob(glob, base: root) }
        .uniq
        .map { |path| File.expand_path(path, root) }
      return paths if reject.empty?

      paths.reject { |path| rejected?(path, reject) }
    end

    def rejected?(path, filters)
      candidate = SourceFile.new(path, NO_COVERAGE_YET, loaded: false)
      filters.any? { |filter| filter.matches?(candidate) }
    end

    no_coverage_yet = {"lines" => []} #: Hash[String, Array[untyped]]
    NO_COVERAGE_YET = no_coverage_yet.freeze
    private_constant :NO_COVERAGE_YET

    # Paths already present are left alone, whoever put them there, which is
    # what lets this run over resultsets a previous SimpleCov already injected
    # into without double-counting or overwriting real data.
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
