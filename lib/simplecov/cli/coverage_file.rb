# frozen_string_literal: true

require_relative "../coverage_json"

module SimpleCov
  module CLI
    # Shared input boundary for commands that consume JSONFormatter's
    # coverage.json. It validates only the stable outer shape, so older schema
    # versions remain readable.
    module CoverageFile
      CRITERIA = {
        line: {label: "Line", percent: "lines_covered_percent",
               covered: "covered_lines", missed: "missed_lines", total: "total_lines"},
        branch: {label: "Branch", percent: "branches_covered_percent",
                 covered: "covered_branches", missed: "missed_branches", total: "total_branches"},
        method: {label: "Method", percent: "methods_covered_percent",
                 covered: "covered_methods", missed: "missed_methods", total: "total_methods"}
      }.freeze

      extend self

      # An exact match, the absolute path or the literal string passed, wins over
      # a suffix match, so a nested "vendor/lib/foo.rb" can't shadow the real
      # "lib/foo.rb" just by sitting earlier in the report. A subpath can end more
      # than one key, and a collision is left as "not found" for the caller rather
      # than scoring whichever key happens to sit first.
      def lookup(coverage_hash, path)
        absolute = File.expand_path(path)
        return [absolute, coverage_hash.fetch(absolute)] if coverage_hash.key?(absolute)
        return [path, coverage_hash.fetch(path)] if coverage_hash.key?(path)

        matches = suffix_matches(coverage_hash, path)
        matches.first if matches.one?
      end

      # The suffix's leading slash keeps "foo.rb" from matching "barfoo.rb", and
      # hoisting it keeps the scan from allocating a string per entry.
      def suffix_matches(coverage_hash, path)
        suffix = "/#{path}"
        coverage_hash.select { |fname, _| fname.end_with?(suffix) }
      end

      # The report's entries under exact, realpath-normalized keys, for
      # programmatic resolution where a suffix fallback could bind a path to the
      # wrong entry. The realpath step keeps a symlinked project root from
      # splitting a resolved path apart from the report's keys.
      def exact_index(coverage_hash)
        index = {} #: Hash[String, untyped]
        coverage_hash.each do |key, payload|
          index[key] ||= payload
          index[normalize(key)] ||= payload
        end
        index
      end

      # A key whose file no longer exists keeps its literal spelling.
      def normalize(key)
        File.realdirpath(key)
      rescue SystemCallError
        key
      end

      # An ambiguous subpath names its candidates: "no entry" would send the user
      # hunting for a typo in a path that exists twice.
      def not_found_message(coverage_hash, path, input)
        matches = suffix_matches(coverage_hash, path).keys
        return "no entry for #{path} in #{input}" if matches.size < 2

        "#{path} matches #{matches.size} files in #{input}: #{matches.sort.join(", ")} " \
          "(use a longer path to pick one)"
      end

      def load_document(path, command:, stderr:)
        CoverageJSON.load(path)
      rescue Errno::ENOENT
        report_missing(stderr, command, path)
      rescue CoverageJSON::Error => e
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
      end

      def report_missing(stderr, command, path)
        stderr.puts("simplecov #{command}: #{path} not found")
      end

      def report_unreadable(stderr, command, path, reason)
        detail = reason.lines.first.to_s.strip
        stderr.puts("simplecov #{command}: cannot read #{path.inspect} (#{detail})")
      end
    end
  end
end
