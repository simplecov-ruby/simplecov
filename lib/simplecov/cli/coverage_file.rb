# frozen_string_literal: true

require_relative "../coverage_json"

module SimpleCov
  module CLI
    # Shared input boundary for commands that consume JSONFormatter's
    # coverage.json. It validates only the stable outer shape so older schema
    # versions remain readable.
    module CoverageFile
      # The coverage.json fields backing each criterion, keyed by the
      # criterion's singular name. The one table the coverage, uncovered,
      # and diff subcommands all read from, so a schema change lands in
      # exactly one place.
      CRITERIA = {
        line: {label: "Line", percent: "lines_covered_percent",
               covered: "covered_lines", total: "total_lines"},
        branch: {label: "Branch", percent: "branches_covered_percent",
                 covered: "covered_branches", total: "total_branches"},
        method: {label: "Method", percent: "methods_covered_percent",
                 covered: "covered_methods", total: "total_methods"}
      }.freeze

    module_function

      # Resolve a user-typed path to its coverage entry. An exact match —
      # the absolute path or the literal string passed — wins over a
      # suffix match, so a nested "vendor/lib/foo.rb" can't shadow the
      # real "lib/foo.rb" just by sitting earlier in the report. The
      # suffix ("/<path>") is the subpath/basename fallback; its leading
      # slash keeps "foo.rb" from matching "barfoo.rb". Exact matches read
      # straight off the hash (O(1)), which the patch subcommand leans on
      # as it looks up every changed file against a large report.
      def lookup(coverage_hash, path)
        absolute = File.expand_path(path)
        return [absolute, coverage_hash[absolute]] if coverage_hash.key?(absolute)
        return [path, coverage_hash[path]] if coverage_hash.key?(path)

        coverage_hash.find { |fname, _| fname.end_with?("/#{path}") }
      end

      def load_document(path, command:, stderr:)
        SimpleCov::CoverageJSON.load(path)
      rescue Errno::ENOENT
        report_missing(stderr, command, path)
      rescue SimpleCov::CoverageJSON::Error => e
        report_invalid(stderr, command, path, e.message)
      rescue SystemCallError => e
        report_unreadable(stderr, command, path, e.message)
      end

      def load_coverage(path, command:, stderr:)
        document = load_document(path, command: command, stderr: stderr)
        return unless document

        none = {} #: Hash[String, untyped]
        coverage = document.fetch("coverage", none)
        return coverage if coverage.is_a?(Hash)

        report_invalid(stderr, command, path, '"coverage" must be an object')
      end

      def report_invalid(stderr, command, path, reason)
        detail = reason.lines.first.to_s.strip
        stderr.puts("simplecov #{command}: input file #{path.inspect} isn't valid JSON (#{detail})")
        nil
      end

      def report_missing(stderr, command, path)
        stderr.puts("simplecov #{command}: #{path} not found")
        nil
      end

      def report_unreadable(stderr, command, path, reason)
        detail = reason.lines.first.to_s.strip
        stderr.puts("simplecov #{command}: cannot read #{path.inspect} (#{detail})")
        nil
      end
    end
  end
end
