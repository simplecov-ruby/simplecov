# frozen_string_literal: true

module SimpleCov
  module CLI
    # The `simplecov help` text. A method so its default paths resolve at
    # call time against the active `.simplecov`.
    module Usage
    module_function

      def text(cli)
        <<~USAGE
          Usage: simplecov <command> [options]

          Commands:
            run <command...>          Execute <command> with simplecov pre-loaded
                                      (so a coverage report is generated even
                                      when the project has no test_helper hook)
            coverage <path>           Print coverage stats for the given file
            report                    Print the overall summary and group totals
            uncovered                 List the lowest-coverage files
            tests [<path>[:<line>]]   List recorded tests for a file or line (needs track_tests)
            affected                  List test files touching code changed since a git ref (needs track_tests)
            merge <files...>          Merge multiple .resultset.json files
            diff <baseline>           Show per-file coverage delta vs baseline
            patch                     Show coverage of the lines a change touched
            open                      Open the HTML report in the default browser
            serve                     Serve the coverage report over HTTP
            clean                     Remove the coverage report directory
            help                      Show this message

          Default paths follow SimpleCov.coverage_dir from a project's
          `.simplecov` when one is present (#{cli.coverage_dir} for this run).

          coverage / report / uncovered / tests / affected / diff / patch options:
            --input PATH              Read from PATH instead of #{cli.default_input}
            --no-color                Disable colorized percentages (also honors NO_COLOR / FORCE_COLOR env)

          coverage options:
            --json                    Print the file's JSON entry verbatim

          report options:
            --json                    Emit totals and group sections as JSON

          uncovered options:
            --threshold N             Only show files below N% coverage
            --top N                   Show at most N files (default: 10)
            --criterion C             line, branch, or method (default: line)
            --json                    Emit results as a JSON array (for CI)

          tests options:
            --json                    Emit the test ids as a JSON array

          affected options:
            --base REF                Diff the working tree against the merge
                                      base of REF and HEAD (default: main)
            --run <command...>        Run <command> (everything after --run) with the
                                      selected test files appended, or bare when
                                      falling back to the full suite; exits with
                                      the command's own status
            --json                    Emit {full_suite, triggers, tests} as a JSON object

          merge options:
            --output PATH             Write merged resultset to PATH
                                      (default: #{cli.default_resultset})
            --honor-timeout           Drop entries older than merge_timeout
            --dry-run                 Print what would be written without writing
            -q, --quiet               Suppress the success status line

          diff options:
            --fail-on-drop            Exit non-zero when any file's coverage
                                      dropped vs the baseline (deleted
                                      files don't count as drops)
            --json                    Emit results as a JSON array (for CI)
            --threshold N             Only show files whose absolute delta
                                      in any criterion is at least N%

          patch options:
            --base REF                Diff against the merge-base of REF
                                      for the touched lines (default: main;
                                      in CI, the PR's target branch)
            --minimum N               Exit non-zero when patch coverage
                                      (covered / coverable touched lines)
                                      is below N%
            --find-renames            Follow a renamed file instead of
                                      counting the moved file as all-new
            --json                    Emit results as a JSON array (for CI)

          open options:
            --report PATH             Open PATH instead of #{cli.default_report}

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
end
