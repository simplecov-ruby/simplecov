# frozen_string_literal: true

require "optparse"
require_relative "color"
require_relative "cli/dotfile"
require_relative "cli/badge"
require_relative "cli/clean"
require_relative "cli/completions"
require_relative "cli/coverage_file"
require_relative "cli/coverage"
require_relative "cli/diff"
require_relative "cli/merge"
require_relative "cli/open"
require_relative "cli/patch"
require_relative "cli/ratchet"
require_relative "cli/report"
require_relative "cli/run"
require_relative "cli/serve"
require_relative "cli/show"
require_relative "cli/status"
require_relative "cli/tests"
require_relative "cli/affected"
require_relative "cli/uncovered"
require_relative "cli/usage"
require_relative "cli/watch"

module SimpleCov
  # Lightweight command-line front-end. `run` dispatches a subcommand
  # (`coverage`, `report`, `uncovered`, `merge`, `diff`, `open`, etc.) —
  # see `Usage.text` for the full list, or run `simplecov help`.
  #
  # Read-only subcommands consume JSONFormatter output (`coverage.json`),
  # which the bundled HTMLFormatter already drops alongside the HTML, so
  # no runtime hooking is needed for those. Default paths follow the
  # project's `.simplecov` `SimpleCov.coverage_dir` setting when one is
  # present, so a project that writes its report somewhere other than
  # `coverage/` doesn't have to pass `--input` / `--report` every
  # invocation.
  module CLI
    COMMANDS = {
      "coverage" => Coverage,
      "show" => Show,
      "run" => Run,
      "open" => Open,
      "report" => Report,
      "status" => Status,
      "uncovered" => Uncovered,
      "tests" => Tests,
      "affected" => Affected,
      "merge" => Merge,
      "diff" => Diff,
      "patch" => Patch,
      "ratchet" => Ratchet,
      "serve" => Serve,
      "watch" => Watch,
      "badge" => Badge,
      "clean" => Clean,
      "completions" => Completions
    }.freeze

  module_function

    # Resolved once per process. Walks up from cwd looking for a
    # `.simplecov`; if present, the file is loaded with
    # `SimpleCov.start` neutered so it can't trigger coverage tracking
    # or an at_exit hook just because we asked it for a config value.
    def coverage_dir
      @coverage_dir ||= Dotfile.coverage_dir
    end

    def default_input
      File.join(coverage_dir, "coverage.json")
    end

    # Resolve "should this subcommand colorize?" once per invocation.
    # `--no-color` (opts[:no_color]) is the per-invocation kill-switch;
    # otherwise we defer to `SimpleCov::Color.enabled?`, which honors
    # `NO_COLOR` / `FORCE_COLOR` and falls back to `stream.tty?`.
    def color_enabled?(opts, stream)
      return false if opts[:no_color]

      SimpleCov::Color.enabled?(stream)
    end

    def default_report
      File.join(coverage_dir, "index.html")
    end

    def default_resultset
      File.join(coverage_dir, ".resultset.json")
    end

    # Returns a process exit status (0 on success, non-zero on error).
    def run(argv, stdout: $stdout, stderr: $stderr)
      command, *rest = argv
      handler = COMMANDS[command]
      return dispatch(handler, command, rest, stdout: stdout, stderr: stderr) if handler
      return stdout.puts(usage) || 0 if [nil, "help", "--help", "-h"].include?(command)

      stderr.puts("simplecov: unknown command #{command.inspect}", usage)
      1
    end

    # One rescue covers every subcommand's OptionParser, so a typo'd
    # flag or a malformed typed argument becomes a one-line error and
    # exit status 1 instead of an unhandled-exception backtrace.
    def dispatch(handler, command, rest, stdout:, stderr:)
      handler.run(rest, stdout: stdout, stderr: stderr)
    rescue CommandHelpers::HelpRequested
      stdout.puts(Usage.for(self, command))
      0
    rescue OptionParser::ParseError => e
      stderr.puts("simplecov #{command}: #{e.message} (run `simplecov help` for usage)")
      1
    end

    def usage
      Usage.text(self)
    end
  end
end
