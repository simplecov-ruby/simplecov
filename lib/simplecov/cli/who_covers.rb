# frozen_string_literal: true

require "json"
require "optparse"
require_relative "command_helpers"
require_relative "coverage"
require_relative "../result_merger/legacy_format_adapter"
require_relative "../result_merger/resultset_file"
require_relative "../combine/lines_combiner"
require_relative "../test_contexts/map"
require_relative "../test_contexts/union"

module SimpleCov
  module CLI
    # `simplecov who-covers <path>:<line>` — name the tests whose
    # recorded contexts covered the given line(s), read straight from
    # `.resultset.json`.
    # rubocop:disable Metrics/ModuleLength -- one subcommand's whole
    # flow (parse, resolve, answer, print); splitting would scatter it
    module WhoCovers
      extend CommandHelpers

    module_function

      TARGET_FORMAT = /\A(?<path>.+):(?<first>\d+)(?:-(?<last>\d+))?\z/

      # The generic derivation would say "whocovers".
      def command_name
        "who-covers"
      end

      MAX_RANGE_LINES = 100_000

      def run(args, stdout:, stderr:)
        opts = parse(args, stderr: stderr)
        return 1 unless opts

        resultset = read_resultset(opts, stderr)
        return 1 unless resultset

        map = contexts_from(resultset, opts, stderr)
        return 1 unless map

        answer(map, resultset, opts, stdout, stderr)
      end

      # An unreadable input (a directory, a permission problem) becomes
      # a one-line error rather than an Errno backtrace.
      def read_resultset(opts, stderr)
        resultset = ResultMerger::ResultsetFile.parse(opts[:input])
        return refuse(stderr, "no results in #{opts[:input]}") if resultset.empty?

        resultset
      rescue SystemCallError => e
        refuse(stderr, "cannot read #{opts[:input]} (#{e.message})")
      end

      def parse(args, stderr:)
        opts, rest = parse_common(args, input: SimpleCov::CLI.default_resultset)
        return nil unless parse_target(opts, rest.first, stderr)

        validate_range(opts, stderr)
      end

      def parse_target(opts, target, stderr)
        match = target&.match(TARGET_FORMAT)
        return refuse(stderr, "expected <path>:<line> or <path>:<start>-<end>") unless match

        opts[:path] = match[:path]
        opts[:first] = Integer(match[:first], 10)
        opts[:last] = match[:last] ? Integer(match[:last], 10) : opts[:first]
        opts
      end

      def validate_range(opts, stderr)
        return refuse(stderr, "line numbers start at 1") if opts[:first] < 1
        return refuse(stderr, "empty line range #{opts[:first]}-#{opts[:last]}") if opts[:last] < opts[:first]
        if opts[:last] - opts[:first] >= MAX_RANGE_LINES
          return refuse(stderr, "line range #{opts[:first]}-#{opts[:last]} spans more than #{MAX_RANGE_LINES} lines")
        end

        opts
      end

      # Like CommandHelpers#error, but signalling "nothing parsed".
      def refuse(stderr, message)
        error(stderr, message)
        nil
      end

      # Mirrors the merge's all-or-drop rule: refuse rather than answer
      # from a partial recording.
      def contexts_from(resultset, opts, stderr)
        union = TestContexts::Union.new
        missing = [] #: Array[String]
        resultset.each do |name, data|
          map = TestContexts::Map.from_hash(data["test_contexts"])
          map ? union.absorb(map) : missing << name
        end
        return union.result if missing.empty?

        refuse(stderr, "no per-test context data for #{missing.sort.join(', ')} in #{opts[:input]}; " \
                       "enable it with `test_contexts :per_test` in your SimpleCov.start block and re-run the suite")
      end

      def answer(map, resultset, opts, stdout, stderr)
        match = Coverage.lookup(coverage_paths(resultset), opts[:path])
        return error(stderr, "no coverage entry for #{opts[:path]} in #{opts[:input]}") unless match

        filename = match.first
        lines = merged_lines(resultset, filename)
        rows = (opts[:first]..opts[:last]).map { |line| line_row(map, filename, lines, line) }
        emit({"file" => filename, "lines" => rows}, opts, stdout)
        0
      end

      # Every measured path, in the hash shape `lookup` matches against.
      def coverage_paths(resultset)
        paths = {} #: Hash[String, nil]
        resultset.each_value { |data| data["coverage"].each_key { |path| paths[path] = nil } }
        paths
      end

      def merged_lines(resultset, filename)
        merged = nil #: Array[Integer?]?
        resultset.each_value do |data|
          lines = ResultMerger::LegacyFormatAdapter.lines_of(data["coverage"][filename])
          merged = Combine::LinesCombiner.merge_into(merged, lines)
        end
        merged
      end

      def line_row(map, filename, lines, line)
        tests = map.tests_for(filename, line)
        count = lines ? lines[line - 1] : nil
        {"line" => line, "status" => line_status(tests, count),
         "tests" => tests.map { |id, name| {"id" => id, "name" => name} }}
      end

      def line_status(tests, count)
        return "covered" unless tests.empty?
        return "not_executable" if count.nil?

        count.positive? ? "setup_only" : "uncovered"
      end

      def emit(payload, opts, stdout)
        return stdout.puts(JSON.pretty_generate(payload)) if opts[:json]

        stdout.puts(payload["file"])
        payload["lines"].each { |row| print_row(row, stdout) }
      end

      SETUP_ONLY = "covered, but by no recorded test (executed during load or setup only)"

      def print_row(row, stdout)
        case row["status"]
        when "covered" then print_covered_row(row, stdout)
        when "setup_only" then stdout.puts("  line #{row['line']}: #{SETUP_ONLY}")
        when "uncovered" then stdout.puts("  line #{row['line']}: not covered")
        else stdout.puts("  line #{row['line']}: not executable")
        end
      end

      def print_covered_row(row, stdout)
        tests = row["tests"]
        stdout.puts("  line #{row['line']}: covered by #{tests.size} #{tests.size == 1 ? 'test' : 'tests'}:")
        tests.each do |test|
          suffix = test["id"] == test["name"] ? "" : " (#{test['id']})"
          stdout.puts("    #{test['name']}#{suffix}")
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
