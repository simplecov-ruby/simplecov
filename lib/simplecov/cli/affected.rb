# frozen_string_literal: true

require "json"
require "optparse"
require_relative "command_helpers"
require_relative "tests"
require_relative "affected/changed_files"
require_relative "affected/selection"

module SimpleCov
  module CLI
    # `simplecov affected`: select the test files whose recorded tests touch the
    # code changed since a git base ref, from a coverage.json written under
    # `track_tests`. The change is everything between the merge base of `--base`
    # and the working tree, plus untracked files.
    #
    # The set intersection is the easy half; the hard half is knowing when to
    # distrust the map, because a test map is stale the moment something changes
    # that no test mentions by name. Any changed file outside the tracked set
    # fails open to the full suite, out loud: each trigger is named on stderr and
    # stdout stays empty, which a bare runner reads as "run everything". Test
    # files always select themselves, recorded or not.
    module Affected
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:)
        opts = parse(args)
        issue = precheck(opts)
        return error(stderr, issue) if issue

        document = CoverageFile.load_document(opts.fetch(:input), command: "affected", stderr: stderr)
        return 1 unless document

        contexts = recorded_contexts(document, opts, stderr)
        return 1 unless contexts

        diffed = ChangedFiles.call(opts[:base] ||= Git.default_base, stderr)
        return 1 unless diffed

        respond(diffed, document, contexts, opts, stdout: stdout, stderr: stderr)
      end

      def parse(args)
        head, runner = split_runner(args)
        opts, rest = parse_common(head, base: nil, run: runner) do |parser, into|
          parser.on("--base REF") { |v| into[:base] = v }
        end
        opts[:rest] = rest
        opts
      end

      # Everything after `--run` is the runner command, verbatim, so the command's
      # own flags never collide with ours.
      def split_runner(args)
        index = args.index("--run")
        return [args, nil] unless index

        [args.take(index), args.drop(index + 1)]
      end

      # A stray positional looks exactly like a forgotten `--base` ref, and
      # silently dropping it would select tests for the wrong change.
      def precheck(opts)
        stray = opts.fetch(:rest).first
        return "unexpected argument #{stray.inspect} (did you mean `--base #{stray}`?)" if stray
        return "missing command after --run" if opts.fetch(:run) && opts.fetch(:run).empty?

        "--run and --json cannot be combined" if opts.fetch(:run) && opts.fetch(:json)
      end

      def respond(diffed, document, contexts, opts, stdout:, stderr:)
        opts[:root] = diffed.fetch(:root)
        return no_changes(opts, stdout, stderr) if diffed.fetch(:changed).empty?

        selection = Selection.build(diffed.fetch(:changed), document, contexts, opts, stderr, root: diffed.fetch(:root))
        return 1 unless selection

        deliver(selection, opts, stdout, stderr)
      end

      def no_changes(opts, stdout, stderr)
        stderr.puts("simplecov affected: no changes against #{opts.fetch(:base)}")
        empty = {tests: [], triggers: []} #: Hash[Symbol, Array[String]]
        emit_json(empty, false, stdout) if opts.fetch(:json)
        0
      end

      def deliver(selection, opts, stdout, stderr)
        full = !selection.fetch(:triggers).empty?
        selection.fetch(:triggers).each { |trigger| stderr.puts("simplecov affected: #{trigger}") }
        stderr.puts("simplecov affected: falling back to the full suite") if full
        return emit_json(selection, full, stdout) if opts.fetch(:json)
        return execute(selection, full, opts, stderr) if opts.fetch(:run)

        emit_text(selection, full, stdout, stderr)
      end

      def emit_json(selection, full, stdout)
        none = [] #: Array[String]
        stdout.puts(JSON.pretty_generate("full_suite" => full, "triggers" => selection.fetch(:triggers),
                                         "tests" => full ? none : selection.fetch(:tests)))
        0
      end

      # Stdout carries the selected files and nothing else, so the list can feed a
      # runner directly, and a full-suite fallback prints nothing, which
      # `rspec $(simplecov affected)` reads as "run everything".
      def emit_text(selection, full, stdout, stderr)
        return 0 if full

        tests = selection.fetch(:tests)
        if tests.empty?
          note_untouched(stderr)
        else
          tests.each { |file| stdout.puts(file) }
          0
        end
      end

      def note_untouched(stderr)
        stderr.puts("simplecov affected: no recorded test touches the changed code")
        0
      end

      def execute(selection, full, opts, stderr)
        return run_command(opts.fetch(:run), opts.fetch(:root), stderr) if full
        return note_untouched(stderr) if selection.fetch(:tests).empty?

        count = selection.fetch(:tests).size
        stderr.puts("simplecov affected: running #{count} test file#{'s' unless count.eql?(1)}")
        run_command(opts.fetch(:run) + selection.fetch(:tests), opts.fetch(:root), stderr)
      end

      # The selection's paths are relative to the repository root, so the runner
      # starts there. The command is named explicitly in the failure because not
      # every engine's exception message carries it.
      def run_command(command, root, stderr)
        _, status = Process.wait2(spawn(*command, chdir: root))
        status.exitstatus || 1
      rescue SystemCallError => e
        stderr.puts("simplecov affected: cannot run #{command.first.inspect} (#{e})")
        127
      end
    end
  end
end
