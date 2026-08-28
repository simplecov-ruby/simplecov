# frozen_string_literal: true

require "json"
require "optparse"
require_relative "command_helpers"
require_relative "tests/redundancy"

module SimpleCov
  module CLI
    # `simplecov tests [<path>[:<line>]]` — list the recorded tests from a
    # coverage.json written under `track_tests`: all of them bare, those
    # touching a file, or those covering one line. Text output is one id
    # per line so the list can feed a test runner directly; empty answers
    # keep stdout empty and note the emptiness on stderr instead.
    module Tests
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:)
        opts = parse(args)
        return error(stderr, "line number must be positive") if opts.fetch(:line)&.zero?

        document = CoverageFile.load_document(opts.fetch(:input), command: "tests", stderr: stderr)
        return 1 unless document

        ids = resolve(document, opts, stderr)
        return 1 unless ids

        emit(ids, opts, stdout, stderr)
        0
      end

      def parse(args)
        opts, rest = parse_common(args) do |parser, options|
          parser.on("--redundant") { options[:redundant] = true }
        end
        opts[:target] = rest.first
        split = split_target(rest.first)
        opts[:path] = split.fetch(:path)
        opts[:line] = split.fetch(:line)
        opts
      end

      # "lib/foo.rb:42" queries a line, anything else a whole file (or,
      # with no argument at all, the whole recording). Only an all-digit
      # tail after the last colon reads as a line number, so Windows
      # drive colons and exotic filenames stay plain paths.
      def split_target(target)
        return {path: nil, line: nil} unless target

        path, sep, tail = target.rpartition(":")
        return {path: target, line: nil} if sep.empty? || !tail.match?(/\A\d+\z/)

        {path: path, line: Integer(tail, 10)}
      end

      # The sorted ids the query selects, or nil after reporting a
      # malformed document or an unanswerable query. `--redundant`
      # intersects the selection with the redundancy sweep, so the flag
      # composes with the path and line narrowing.
      def resolve(document, opts, stderr)
        contexts = recorded_contexts(document, opts, stderr)
        return unless contexts

        opts[:no_recording] = contexts.empty?
        ids = selected_ids(document, contexts, opts, stderr)
        return ids unless ids && opts[:redundant]

        redundant = Redundancy.redundant_ids(document, contexts, opts, stderr)
        redundant && (ids & redundant)
      end

      def selected_ids(document, contexts, opts, stderr)
        return contexts.sort unless opts.fetch(:path)

        entry = locate_entry(document, opts, stderr)
        return unless entry

        table = context_table(entry, contexts, opts, stderr)
        table && ids_from(table, contexts, opts.fetch(:line))
      end

      def locate_entry(document, opts, stderr)
        coverage = document["coverage"]
        input = opts.fetch(:input)
        unless coverage.is_a?(Hash)
          return CoverageFile.report_invalid(stderr, "tests", input, '"coverage" must be an object')
        end

        path = opts.fetch(:path)
        match = CoverageFile.lookup(coverage, path)
        return error_nil(stderr, CoverageFile.not_found_message(coverage, path, input)) unless match
        # A found entry of the wrong type is malformed input, not a
        # missing file — the same distinction `simplecov coverage` draws.
        return match.last if match.last.is_a?(Hash)

        CoverageFile.report_invalid(stderr, "tests", input, "entry for #{path} must be an object")
      end

      # The file's decoded `index => bitmap` table. An absent key is an
      # untouched file (empty table); anything malformed — a foreign
      # index, a non-hex bitmap — poisons the whole answer, matching the
      # all-or-nothing tolerance the resultset reader applies.
      def context_table(entry, contexts, opts, stderr)
        raw = entry["contexts"] || {}
        table = decode_table(raw, contexts.size) if raw.is_a?(Hash)
        return table if table

        CoverageFile.report_invalid(stderr, "tests", opts.fetch(:input),
                                    "entry for #{opts.fetch(:path)} carries a malformed \"contexts\" table")
      end

      def decode_table(raw, context_count)
        table = {} #: Hash[Integer, Integer]
        raw.each do |index, hex|
          # Both halves arrive from JSON, so both are plain strings: a
          # decimal index naming a recorded test, and a hexadecimal
          # bitmap of the lines it covered.
          return nil unless index.is_a?(String) && index.match?(/\A\d+\z/)
          return nil unless hex.is_a?(String) && hex.match?(/\A\h+\z/)

          position = Integer(index, 10)
          return nil unless position < context_count

          table[position] = Integer(hex, 16)
        end
        table
      end

      def ids_from(table, contexts, line)
        bit = line && (1 << (line - 1))
        table.filter_map { |index, bitmap| contexts.fetch(index) if bit.nil? || bitmap.anybits?(bit) }.sort
      end

      def emit(ids, opts, stdout, stderr)
        return stdout.puts(JSON.pretty_generate(ids)) if opts.fetch(:json)
        return note_empty(opts, stderr) if ids.empty?

        ids.each { |id| stdout.puts(id) }
      end

      # Stdout stays reserved for ids, so an empty answer explains itself
      # on stderr — naming the query when there was one. An empty
      # `--redundant` answer over a real recording is good news and says
      # so, but an empty recording keeps the plainer message: nothing was
      # recorded, so nothing was proven unique.
      def note_empty(opts, stderr)
        stderr.puts("simplecov tests: #{empty_message(opts)}")
      end

      def empty_message(opts)
        target = opts.fetch(:target)
        if opts[:redundant] && !opts.fetch(:no_recording)
          return "no redundant test covers #{target}" if target

          "no redundant tests, every recorded test covers at least one line uniquely"
        elsif target
          "no recorded test covers #{target}"
        else
          "no tests recorded"
        end
      end
    end
  end
end
