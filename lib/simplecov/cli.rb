# frozen_string_literal: true

require "optparse"
require_relative "color"
require_relative "cli/dotfile"
require_relative "cli/badge"
require_relative "cli/clean"
require_relative "cli/completions"
require_relative "cli/coverage_file"
require_relative "cli/coverage"
require_relative "cli/dead_code"
require_relative "cli/diff"
require_relative "cli/history"
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
  # Lightweight command-line front-end. Read-only subcommands consume
  # JSONFormatter output, which the bundled HTMLFormatter already drops
  # alongside the HTML, so no runtime hooking is needed for those. Default
  # paths follow the project's `.simplecov` `coverage_dir` setting when one is
  # present.
  module CLI
    COMMANDS = {
      "coverage" => Coverage,
      "show" => Show,
      "run" => Run,
      "open" => Open,
      "report" => Report,
      "status" => Status,
      "history" => History,
      "uncovered" => Uncovered,
      "tests" => Tests,
      "affected" => Affected,
      "merge" => Merge,
      "diff" => Diff,
      "patch" => Patch,
      "ratchet" => Ratchet,
      "dead-code" => DeadCode,
      "serve" => Serve,
      "watch" => Watch,
      "badge" => Badge,
      "clean" => Clean,
      "completions" => Completions
    }.freeze

    extend self

    # Resolved once per process, by walking up from cwd for a `.simplecov` and
    # loading it with `SimpleCov.start` neutered so it can't trigger tracking
    # just because we asked it for a config value.
    def coverage_dir
      @coverage_dir ||= Dotfile.coverage_dir
    end

    def default_input
      File.join(coverage_dir, "coverage.json")
    end

    def color_enabled?(opts, stream)
      return false if opts[:no_color]

      Color.enabled?(stream)
    end

    def default_report
      File.join(coverage_dir, "index.html")
    end

    def default_resultset
      File.join(coverage_dir, ".resultset.json")
    end

    def run(argv, stdout: $stdout, stderr: $stderr)
      command, *rest = argv
      handler = COMMANDS[command]
      return dispatch(handler, command, rest, stdout: stdout, stderr: stderr) if handler
      return stdout.puts(usage) || 0 if [nil, "help", "--help", "-h"].include?(command)

      stderr.puts("simplecov: unknown command #{command.inspect}", usage)
      1
    end

    # One rescue covers every subcommand's OptionParser, so a typo'd flag becomes
    # a one-line error and exit status 1 instead of a backtrace.
    def dispatch(handler, command, rest, stdout:, stderr:)
      handler.run(rest, stdout: stdout, stderr: stderr)
    rescue CommandHelpers::HelpRequested
      stdout.puts(Usage.for(self, command))
      0
    rescue OptionParser::ParseError => e
      stderr.puts("simplecov #{command}: #{e} (run `simplecov help` for usage)")
      1
    end

    def usage
      Usage.text(self)
    end
  end
end
