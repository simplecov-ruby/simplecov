# frozen_string_literal: true

require_relative "color"
require_relative "cli/dotfile"
require_relative "cli/clean"
require_relative "cli/coverage"
require_relative "cli/diff"
require_relative "cli/merge"
require_relative "cli/open"
require_relative "cli/report"
require_relative "cli/run"
require_relative "cli/serve"
require_relative "cli/uncovered"

module SimpleCov
  # Lightweight command-line front-end. `run` dispatches a subcommand
  # (`coverage`, `report`, `uncovered`, `merge`, `diff`, `open`, etc.) —
  # see the `usage` text below for the full list, or run `simplecov help`.
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
      "run" => Run,
      "open" => Open,
      "report" => Report,
      "uncovered" => Uncovered,
      "merge" => Merge,
      "diff" => Diff,
      "serve" => Serve,
      "clean" => Clean
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
      return handler.run(rest, stdout: stdout, stderr: stderr) if handler
      return stdout.puts(usage) || 0 if [nil, "help", "--help", "-h"].include?(command)

      stderr.puts("simplecov: unknown command #{command.inspect}", usage)
      1
    end

    def usage
      <<~USAGE
        Usage: simplecov <command> [options]

        Commands:
          run <command...>          Execute <command> with simplecov pre-loaded
                                    (so a coverage report is generated even
                                    when the project has no test_helper hook)
          coverage <path>           Print coverage stats for the given file
          report                    Print the overall summary and group totals
          uncovered                 List the lowest-coverage files
          merge <files...>          Merge multiple .resultset.json files
          diff <baseline>           Show per-file coverage delta vs baseline
          open                      Open the HTML report in the default browser
          serve                     Serve the coverage report over HTTP
          clean                     Remove the coverage report directory
          help                      Show this message

        Default paths follow SimpleCov.coverage_dir from a project's
        `.simplecov` when one is present (#{coverage_dir} for this run).

        coverage / report / uncovered / diff options:
          --input PATH              Read from PATH instead of #{default_input}
          --no-color                Disable colorized percentages
                                    (also honors NO_COLOR / FORCE_COLOR env)

        coverage options:
          --json                    Print the file's JSON entry verbatim

        report options:
          --json                    Emit totals and group sections as JSON

        uncovered options:
          --threshold N             Only show files below N% coverage
          --top N                   Show at most N files (default: 10)
          --criterion C             line, branch, or method (default: line)
          --json                    Emit results as a JSON array (for CI)

        merge options:
          --output PATH             Write merged resultset to PATH
                                    (default: #{default_resultset})
          --honor-timeout           Drop entries older than merge_timeout
          --dry-run                 Print what would be written without
                                    actually writing
          -q, --quiet               Suppress the success status line

        diff options:
          --fail-on-drop            Exit non-zero when any file's coverage
                                    dropped vs the baseline
          --json                    Emit results as a JSON array (for CI)
          --threshold N             Only show files whose absolute delta
                                    in any criterion is at least N%

        open options:
          --report PATH             Open PATH instead of #{default_report}

        serve options:
          --port N                  Bind to port N (default: random open port)
          --host HOST               Bind to HOST (default: 127.0.0.1)

        clean options:
          --dry-run                 Print what would be removed without
                                    deleting anything
          -q, --quiet               Suppress status lines
      USAGE
    end
  end
end
