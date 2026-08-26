# frozen_string_literal: true

module SimpleCov
  module CLI
    # The `simplecov help` text. A method so its default paths resolve at
    # call time against the active `.simplecov`.
    #
    # rubocop:disable Metrics/ModuleLength -- the module is one usage
    # document; its length is the command surface, not logic.
    module Usage
    module_function

      # The full text filtered to one command, for `<command> --help`:
      # a usage line, the command's row from the Commands table, and
      # every options section that names it.
      def for(cli, command)
        sections = text(cli).split("\n\n")
        row = sections.fetch(1).lines.find { |line| line.match?(/\A  #{Regexp.escape(command)}[ \[]/) }
        options = sections.select { |section| section_for?(section, command) }
        ["Usage: simplecov #{command} [options]", row&.strip, *options].compact.join("\n\n")
      end

      def section_for?(section, command)
        header = section.lines.first.to_s.strip
        header.end_with?("options:") && header.delete_suffix("options:").split(%r{[\s/]+}).include?(command)
      end

      def text(cli)
        <<~USAGE
          Usage: simplecov <command> [options]

          Commands:
            run <command...>          Execute <command> with SimpleCov pre-loaded
                                      (works without a test_helper hook)
            coverage <path>           Print coverage stats for the given file
            show <path>               Print the file's source annotated with hit counts and misses
            report                    Print the overall summary and group totals
            status                    Report freshness: age, commit distance, recorded tests
            history                   Print the recorded coverage trend, a sparkline per criterion
            badge                     Render the coverage percent as an SVG badge
            uncovered                 List the lowest-coverage files
            tests [<path>[:<line>]]   List recorded tests for a file or line (needs track_tests)
            affected                  List test files touching code changed since a git ref (needs track_tests)
            merge <files...>          Merge multiple .resultset.json files
            diff <baseline>           Show per-file coverage delta vs baseline
            patch                     Show coverage of the lines a change touched
            ratchet                   Rewrite the per-file coverage baseline, only ever tightening
            dead-code                 Cross production coverage with the report to find dead code
            open                      Open the HTML report in the default browser
            serve                     Serve the coverage report over HTTP
            watch <command...>        Re-run <command> on save and live-reload the served report
            clean                     Remove the coverage report directory
            completions <shell>       Emit the completion script for fish, bash, or zsh
            help                      Show this message

          Every command answers `--help` / `-h`. Default paths follow a project's
          `.simplecov` SimpleCov.coverage_dir (#{cli.coverage_dir} for this run).

          coverage / show / report / status / uncovered / tests / affected / diff / patch / ratchet / dead-code options:
            --input PATH              Read from PATH instead of #{cli.default_input}
            --no-color                Disable colorized percentages (also honors NO_COLOR / FORCE_COLOR env)

          coverage options:
            --json                    Print the file's JSON entry verbatim

          show options:
            --uncovered-only          Print only <path>:<ranges> of the missed lines
            --json                    Emit path, missed lines, per-line hits, and markers as JSON

          report options:
            --json                    Emit totals and group sections as JSON

          status options:
            --json                    Emit the freshness facts as a JSON object

          history options:
            --input PATH              Read from PATH instead of the coverage directory's .history.json
            --file PATH               Follow one file's trajectory instead of the totals
            --json                    Emit the entries (or the file's trajectory) as JSON
            --no-color                Disable colorized deltas (also honors NO_COLOR / FORCE_COLOR env)

          badge options:
            --input PATH              Read from PATH instead of #{cli.default_input}
            --output PATH             Write the badge to PATH instead of stdout
            --criterion C             line, branch, or method (default: line)
            --label TEXT              The badge's left-side text (default: the criterion's, like "line coverage")

          uncovered options:
            --threshold N             Only show files below N% coverage
            --top N                   Show at most N files (default: 10)
            --criterion C             line, branch, or method (default: line)
            --missing                 Append the missed line ranges to each row
            --annotate github         Emit ::warning workflow commands instead of rows
            --json                    Emit results as a JSON array (for CI)

          tests options:
            --redundant               List only tests whose covered lines other tests also cover
            --json                    Emit the test ids as a JSON array

          affected options:
            --base REF                Diff against the merge base of REF and HEAD (default: origin's HEAD, else main)
            --run <command...>        Run <command> (all args after --run) with the selection appended, or bare on a full-suite fallback, exiting with the command's status
            --json                    Emit {full_suite, triggers, tests} as a JSON object

          merge options:
            --output PATH             Write merged resultset to PATH (default: #{cli.default_resultset})
            --honor-timeout           Drop entries older than merge_timeout
            --dry-run                 Print what would be written without writing
            -q, --quiet               Suppress the success status line

          diff options:
            --fail-on-drop            Exit non-zero when any file's coverage dropped vs baseline (deletions don't count)
            --json                    Emit results as a JSON array (for CI)
            --threshold N             Only show files whose absolute delta in any criterion is at least N%

          patch options:
            --base REF                Diff against the merge-base of REF for the touched lines (default: origin's HEAD, else main, or in CI the PR's target branch)
            --minimum N               Exit non-zero when patch coverage on any measured criterion is below N%
            --find-renames            Follow a renamed file instead of counting the moved file as all-new
            --json                    Emit results as a JSON array (for CI)

          dead-code options:
            --production PATH         The production coverage file a SimpleCov::Production sink wrote (default: the project's `production_coverage`, required when none is configured)
            --untested-in-production  Print code production runs that no test covers, instead of the dead rows
            --json                    Emit every category (dead, possibly dead, untested in production) as JSON

          ratchet options:
            --baseline PATH           The baseline file to rewrite (default: the project's `baseline_file`, .simplecov_baseline.yml)
            --init                    Regenerate from scratch: add entries for new files and reset every floor to the current state
            --dry-run                 Print what would change without writing
            --json                    Emit the summary (tightened / pruned / regressed entries) as JSON

          open options:
            --report PATH             Open PATH instead of #{cli.default_report}

          serve options:
            --port N                  Bind to port N (default: random open port)
            --host HOST               Bind to HOST (default: 127.0.0.1)

          watch options:
            --port N                  Bind to port N (default: random open port)
            --host HOST               Bind to HOST (default: 127.0.0.1)
            --interval SECONDS        Poll the tracked files this often (default: 0.5)
            --open                    Open the served report in the default browser

          clean options:
            --dry-run                 Print what would be removed without deleting
            -q, --quiet               Suppress status lines
        USAGE
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
