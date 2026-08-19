# frozen_string_literal: true

require "json"
require "optparse"
require_relative "command_helpers"
require_relative "tests"
require_relative "affected/changed_files"
require_relative "affected/selection"

module SimpleCov
  module CLI
    # `simplecov affected` — select the test files whose recorded tests
    # touch the code changed since a git base ref, from a coverage.json
    # written under `track_tests`. The change is everything between the
    # merge base of `--base` and HEAD and the working tree (so
    # uncommitted work counts, and commits that landed on the base after
    # the branch point don't), plus untracked files. The set
    # intersection is the easy half; the hard half is knowing when to
    # distrust the map, because a test
    # map is stale the moment something changes that no test mentions by
    # name. Any changed file outside the tracked set — a lockfile, a spec
    # helper, the runner configuration, anything the report has no data
    # for — fails open to the full suite, out loud: each trigger is named
    # on stderr and stdout stays empty, which a bare runner reads as
    # "run everything". Test files always select themselves, recorded or
    # not, and `--run <command...>` hands the answer straight to a runner.
    module Affected
      extend CommandHelpers

    module_function

      def run(args, stdout:, stderr:)
        opts = parse(args)
        issue = precheck(opts)
        return error(stderr, issue) if issue

        document = CoverageFile.load_document(opts[:input], command: "affected", stderr: stderr)
        return 1 unless document

        contexts = recorded_contexts(document, opts, stderr)
        return 1 unless contexts

        diffed = ChangedFiles.call(opts[:base], stderr)
        return 1 unless diffed

        respond(diffed, document, contexts, opts, stdout: stdout, stderr: stderr)
      end

      def parse(args)
        head, runner = split_runner(args)
        opts, rest = parse_common(head, base: "main", run: runner) do |parser, into|
          parser.on("--base REF") { |v| into[:base] = v }
        end
        opts[:rest] = rest
        opts
      end

      # Everything after `--run` is the runner command, verbatim, so the
      # command's own flags never collide with ours; the head is parsed
      # normally.
      def split_runner(args)
        index = args.index("--run")
        return [args, nil] unless index

        [args.take(index), args.drop(index + 1)]
      end

      # A stray positional looks exactly like a forgotten `--base` ref,
      # and silently dropping it would select tests for the wrong change,
      # so it's an error rather than ignored.
      def precheck(opts)
        stray = opts[:rest].first
        return "unexpected argument #{stray.inspect} (did you mean `--base #{stray}`?)" if stray
        return "missing command after --run" if opts[:run] && opts[:run].empty?

        "--run and --json cannot be combined" if opts[:run] && opts[:json]
      end

      def respond(diffed, document, contexts, opts, stdout:, stderr:)
        opts[:root] = diffed[:root]
        return no_changes(opts, stdout, stderr) if diffed[:changed].empty?

        selection = Selection.build(diffed[:changed], document, contexts, opts, stderr, root: diffed[:root])
        return 1 unless selection

        deliver(selection, opts, stdout, stderr)
      end

      def no_changes(opts, stdout, stderr)
        stderr.puts("simplecov affected: no changes against #{opts[:base]}")
        empty = {tests: [], triggers: []} #: Hash[Symbol, Array[String]]
        emit_json(empty, false, stdout) if opts[:json]
        0
      end

      def deliver(selection, opts, stdout, stderr)
        full = !selection[:triggers].empty?
        selection[:triggers].each { |trigger| stderr.puts("simplecov affected: #{trigger}") }
        stderr.puts("simplecov affected: falling back to the full suite") if full
        return emit_json(selection, full, stdout) if opts[:json]
        return execute(selection, full, opts, stderr) if opts[:run]

        emit_text(selection, full, stdout, stderr)
      end

      def emit_json(selection, full, stdout)
        none = [] #: Array[String]
        stdout.puts(JSON.pretty_generate("full_suite" => full, "triggers" => selection[:triggers],
                                         "tests" => full ? none : selection[:tests]))
        0
      end

      # Stdout carries the selected files and nothing else, so the list
      # can feed a runner directly — and a full-suite fallback prints
      # nothing, which `rspec $(simplecov affected)` reads as "run
      # everything".
      def emit_text(selection, full, stdout, stderr)
        return 0 if full
        return note_untouched(stderr) if selection[:tests].empty?

        selection[:tests].each { |file| stdout.puts(file) }
        0
      end

      def note_untouched(stderr)
        stderr.puts("simplecov affected: no recorded test touches the changed code")
        0
      end

      def execute(selection, full, opts, stderr)
        return run_command(opts[:run], opts[:root], stderr) if full
        return note_untouched(stderr) if selection[:tests].empty?

        count = selection[:tests].size
        stderr.puts("simplecov affected: running #{count} test file#{'s' unless count == 1}")
        run_command(opts[:run] + selection[:tests], opts[:root], stderr)
      end

      # The selection's paths are relative to the repository root, so the
      # runner starts there — a no-op for the usual root-level invocation,
      # and what makes the appended paths resolve for a subdirectory one.
      def run_command(command, root, stderr)
        _, status = Process.wait2(spawn(*command, chdir: root))
        status.exitstatus || 1
      rescue SystemCallError => e
        # The command is named explicitly because not every engine's
        # exception message carries it (JRuby's ENOENT does not).
        stderr.puts("simplecov affected: cannot run #{command.first.inspect} (#{e.message})")
        127
      end
    end
  end
end
