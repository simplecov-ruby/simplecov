# frozen_string_literal: true

require "json"
require "optparse"

module SimpleCov
  # Lightweight command-line front-end.
  #
  # Currently supports a single subcommand:
  #
  #   simplecov coverage <path>   Print stats for the given file from
  #                               coverage/coverage.json (or --input PATH).
  #
  # Reads from JSONFormatter output, which is already produced as a
  # side-effect of the bundled HTMLFormatter, so no runtime hooking is
  # needed — the CLI is purely a reader.
  module CLI
    DEFAULT_INPUT = "coverage/coverage.json"

  module_function

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
          help                      Show this message

        coverage / report / uncovered / diff options:
          --input PATH              Read from PATH instead of #{DEFAULT_INPUT}

        coverage options:
          --json                    Print the file's JSON entry verbatim

        report options:
          --json                    Emit totals and group sections as JSON

        uncovered options:
          --threshold N             Only show files below N% line coverage
          --top N                   Show at most N files (default: 10)
          --json                    Emit results as a JSON array (for CI)

        merge options:
          --output PATH             Write merged resultset to PATH
                                    (default: coverage/.resultset.json)
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
          --report PATH             Open PATH instead of coverage/index.html
      USAGE
    end

    # `simplecov coverage <path>` — print per-criterion stats for one
    # file from a JSONFormatter coverage.json.
    module Coverage
      CRITERIA = [
        {label: "Line",   pct: "lines_covered_percent",    cov: "covered_lines",    tot: "total_lines"},
        {label: "Branch", pct: "branches_covered_percent", cov: "covered_branches", tot: "total_branches"},
        {label: "Method", pct: "methods_covered_percent",  cov: "covered_methods",  tot: "total_methods"}
      ].freeze

    module_function

      def run(args, stdout:, stderr:)
        opts = parse(args, stderr: stderr)
        return 1 unless opts

        match = locate_match(opts, stderr)
        return 1 unless match

        emit(match, opts, stdout)
        0
      end

      def parse(args, stderr:)
        opts = {input: DEFAULT_INPUT, json: false}
        rest =
          OptionParser.new do |o|
            o.on("--input PATH") { |v| opts[:input] = v }
            o.on("--json") { opts[:json] = true }
          end.parse(args)
        return stderr.puts("simplecov coverage: missing file argument") && nil if rest.empty?

        opts[:path] = rest.first
        opts
      end

      def locate_match(opts, stderr)
        return stderr.puts("simplecov coverage: #{opts[:input]} not found") && nil unless File.exist?(opts[:input])

        data = JSON.parse(File.read(opts[:input]))
        match = lookup(data.fetch("coverage", {}), opts[:path])
        return match if match

        stderr.puts("simplecov coverage: no entry for #{opts[:path]} in #{opts[:input]}")
        nil
      end

      # Match either the absolute path, the literal string passed, or
      # any coverage entry whose absolute filename ends with "/<path>".
      # That covers the three natural ways a user types a path: relative
      # to project root ("app/foo.rb"), absolute, or basename-only.
      def lookup(coverage_hash, path)
        absolute = File.expand_path(path)
        suffix   = "/#{path}"
        coverage_hash.each do |fname, payload|
          return [fname, payload] if fname == absolute || fname == path || fname.end_with?(suffix)
        end
        nil
      end

      def emit(match, opts, stdout)
        filename, payload = match
        if opts[:json]
          stdout.puts(JSON.pretty_generate(filename => payload))
        else
          print_human(filename, payload, stdout)
        end
      end

      def print_human(filename, payload, stdout)
        stdout.puts(filename)
        CRITERIA.each { |c| emit_criterion(stdout, payload, c) }
      end

      def emit_criterion(stdout, payload, criterion)
        return unless payload.key?(criterion[:pct])

        stdout.puts(format("  %<label>-7s %<pct>.2f%% (%<covered>d / %<total>d)",
                           label: "#{criterion[:label]}:",
                           pct: payload[criterion[:pct]],
                           covered: payload[criterion[:cov]] || 0,
                           total: payload[criterion[:tot]] || 0))
      end
    end

    # `simplecov run <command...>` — exec the given command with
    # simplecov auto-loaded so a coverage report drops into the
    # project's coverage/ directory at the end. Useful for projects
    # without a test_helper that already calls SimpleCov.start (e.g.
    # plain `bundle exec rake test` on an unconfigured library).
    module Run
      AUTOSTART = File.expand_path("autostart", __dir__)

    module_function

      def run(args, stderr:, **)
        cmd = args.first == "--" ? args.drop(1) : args
        if cmd.empty?
          stderr.puts("simplecov run: missing command")
          return 1
        end

        Kernel.exec(rubyopt_env, *cmd)
      rescue Errno::ENOENT => e
        stderr.puts("simplecov run: #{e.message}")
        127
      end

      def rubyopt_env
        existing = ENV["RUBYOPT"].to_s.strip
        injection = "-r#{AUTOSTART}"
        merged = existing.empty? ? injection : "#{existing} #{injection}"
        ENV.to_hash.merge("RUBYOPT" => merged)
      end
    end

    # `simplecov open [--report PATH]` — open the HTML report in the
    # platform's default browser. Tiny QoL wrapper around `xdg-open` /
    # `open` / `start` so users don't have to type a file:// URL.
    module Open
      DEFAULT_REPORT = "coverage/index.html"

    module_function

      def run(args, stderr:, **)
        path = parse(args)
        return error(stderr, "#{path} not found") unless File.exist?(path)

        opener = browser_opener
        return error(stderr, "no known opener for #{RbConfig::CONFIG['host_os']}") unless opener

        system(*opener, path) ? 0 : 1
      end

      def error(stderr, message)
        stderr.puts("simplecov open: #{message}")
        1
      end

      def parse(args)
        path = DEFAULT_REPORT
        OptionParser.new do |o|
          o.on("--report PATH") { |v| path = v }
        end.parse(args)
        path
      end

      # Returns the argv for the platform's "open this file" command, or
      # nil if the host OS isn't recognized. On Windows, `start` is a
      # cmd.exe builtin (not an executable), so route through `cmd /c`;
      # the empty string is the window-title positional `start` takes
      # before the path so a quoted path isn't mis-parsed as the title.
      def browser_opener
        case RbConfig::CONFIG["host_os"]
        when /darwin/                       then ["open"]
        when /mswin|mingw|cygwin/           then ["cmd", "/c", "start", ""]
        when /linux|bsd|solaris/            then ["xdg-open"]
        end
      end
    end

    # `simplecov report [--input PATH]` — pretty-print the overall
    # totals row plus per-group totals from a JSONFormatter
    # coverage.json. Same numbers as the HTML report's totals row, for
    # contexts where opening a browser isn't an option (CI logs, ssh
    # sessions, terminal-only workflows).
    module Report
      SECTIONS = [%w[Line lines], %w[Branch branches], %w[Method methods]].freeze

    module_function

      def run(args, stdout:, stderr:)
        opts = parse(args)
        return 1 unless (data = load_data(opts[:input], stderr))

        opts[:json] ? emit_json(stdout, data) : emit_text(stdout, data)
        0
      end

      def parse(args)
        input = DEFAULT_INPUT
        json = false
        OptionParser.new do |o|
          o.on("--input PATH") { |v| input = v }
          o.on("--json")       { json = true }
        end.parse(args)
        {input: input, json: json}
      end

      def load_data(input, stderr)
        return JSON.parse(File.read(input)) if File.exist?(input)

        stderr.puts("simplecov report: #{input} not found")
        nil
      end

      def emit_text(stdout, data)
        emit_totals(stdout, "All Files", data.fetch("total", {}))
        data.fetch("groups", {}).each { |name, group| emit_totals(stdout, name, group) }
      end

      def emit_totals(stdout, label, totals)
        stdout.puts(label)
        SECTIONS.each { |display, key| emit_section(stdout, display, totals[key]) }
        stdout.puts
      end

      def emit_section(stdout, display, section)
        return unless section.is_a?(Hash) && section["total"].to_i.positive?

        stdout.puts(format("  %<label>-7s %<pct>.2f%% (%<covered>d / %<total>d)",
                           label: "#{display}:",
                           pct: section["percent"],
                           covered: section["covered"] || 0,
                           total: section["total"] || 0))
      end

      def emit_json(stdout, data)
        payload = {"All Files" => collect_section(data.fetch("total", {}))}
        data.fetch("groups", {}).each { |name, group| payload[name] = collect_section(group) }
        stdout.puts(JSON.pretty_generate(payload))
      end

      def collect_section(totals)
        SECTIONS.each_with_object({}) do |(_, key), out|
          section = totals[key]
          next unless section.is_a?(Hash) && section["total"].to_i.positive?

          out[key] = {"percent" => section["percent"], "covered" => section["covered"], "total" => section["total"]}
        end
      end
    end

    # `simplecov uncovered [--threshold N] [--top N]` — list the
    # lowest-coverage files (by line coverage, ascending), so a
    # developer can answer "where should I add tests next?" without
    # opening a browser. Reads coverage.json directly.
    module Uncovered
      DEFAULT_TOP = 10

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        return 1 unless (data = Report.load_data(opts[:input], stderr))

        files = rank(data.fetch("coverage", {}), opts[:threshold]).first(opts[:top])
        return stdout.puts(empty_message(opts[:json])) || 0 if files.empty?

        opts[:json] ? emit_json(stdout, files) : emit_text(stdout, files)
        0
      end

      def parse(args)
        opts = {input: DEFAULT_INPUT, threshold: 100.0, top: DEFAULT_TOP}
        OptionParser.new do |o|
          o.on("--input PATH")         { |v| opts[:input] = v }
          o.on("--threshold N", Float) { |v| opts[:threshold] = v }
          o.on("--top N", Integer)     { |v| opts[:top] = v }
          o.on("--json")               { opts[:json] = true }
        end.parse(args)
        opts
      end

      def emit_text(stdout, files)
        files.each { |fname, pct, covered, total| stdout.puts(format_row(fname, pct, covered, total)) }
      end

      def emit_json(stdout, files)
        rows = files.map do |fname, pct, covered, total|
          {"file" => fname, "percent" => pct, "covered" => covered, "total" => total}
        end
        stdout.puts(JSON.pretty_generate(rows))
      end

      def empty_message(json)
        json ? "[]" : "simplecov uncovered: nothing to report"
      end

      def rank(coverage_hash, threshold)
        rows = coverage_hash.filter_map { |fname, payload| row_for(fname, payload, threshold) }
        rows.sort_by { |_fname, pct, _c, _t| pct }
      end

      def row_for(fname, payload, threshold)
        return unless payload.is_a?(Hash) && payload["total_lines"].to_i.positive?

        pct = payload["lines_covered_percent"].to_f
        return if pct >= threshold

        [fname, pct, payload["covered_lines"].to_i, payload["total_lines"].to_i]
      end

      def format_row(fname, pct, covered, total)
        format("%<pct>6.2f%%  %<covered>d/%<total>d  %<fname>s",
               pct: pct, covered: covered, total: total, fname: fname)
      end
    end

    # `simplecov merge <files...>` — wrap SimpleCov::ResultMerger so a
    # CI matrix that produces one .resultset.json per worker can stitch
    # them together from the shell instead of dropping a Rake task into
    # every project. Requires the full simplecov library to be on the
    # load path; lazy-required so the read-only subcommands above don't
    # pay for ResultMerger (and its Coverage runtime guard).
    module Merge
    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        return error(stderr, "missing input files") if opts[:files].empty?
        return 1 unless valid_inputs?(opts[:files], stderr)

        require "simplecov"
        result = SimpleCov::ResultMerger.merge_results(*opts[:files], ignore_timeout: !opts[:honor_timeout])
        return error(stderr, "no mergeable results in input files") unless result

        commit(opts, result, stdout)
        0
      end

      def commit(opts, result, stdout)
        verb = opts[:dry_run] ? "would write" : "wrote"
        write(opts[:output], result) unless opts[:dry_run]
        stdout.puts("simplecov merge: #{verb} #{opts[:output]}") unless opts[:quiet]
      end

      def valid_inputs?(files, stderr)
        parsed = parse_inputs(files, stderr) or return false

        warn_about_duplicate_command_names(parsed, stderr)
        true
      end

      def parse(args)
        opts = {output: "coverage/.resultset.json", honor_timeout: false, dry_run: false, quiet: false}
        files =
          OptionParser.new do |o|
            o.on("--output PATH") { |v| opts[:output] = v }
            o.on("--honor-timeout") { opts[:honor_timeout] = true }
            o.on("--dry-run") { opts[:dry_run] = true }
            o.on("-q", "--quiet") { opts[:quiet] = true }
          end.parse(args)
        opts.merge(files: files)
      end

      # Validate every input file up-front and return a {path => parsed}
      # hash. Surfacing per-file errors here turns ResultMerger's
      # generic "no mergeable results" into a message that points at
      # the specific input causing the failure.
      def parse_inputs(files, stderr)
        files.each_with_object({}) do |path, memo|
          data = parse_input(path, stderr) or return nil

          memo[path] = data
        end
      end

      def parse_input(path, stderr)
        return parse_input_error(stderr, path, "not found") unless File.exist?(path)

        data = JSON.parse(File.read(path))
        return data if data.is_a?(Hash) && !data.empty?

        parse_input_error(stderr, path, "has no resultset entries")
      rescue JSON::ParserError => e
        parse_input_error(stderr, path, "isn't valid JSON (#{e.message})")
      end

      def parse_input_error(stderr, path, reason)
        stderr.puts("simplecov merge: input file #{path.inspect} #{reason}")
        nil
      end

      # When two input files share a command_name, ResultMerger folds
      # them together with last-write-wins on the timestamp — easy to
      # mistake for "no merge happened." Surface the overlap so the
      # operator can rename the workers or accept the merge knowingly.
      def warn_about_duplicate_command_names(parsed, stderr)
        files_per_command = parsed.each_with_object({}) do |(path, data), memo|
          data.each_key { |command_name| (memo[command_name] ||= []) << path }
        end
        files_per_command.each do |command_name, paths|
          next if paths.size < 2

          stderr.puts(duplicate_warning(command_name, paths))
        end
      end

      def duplicate_warning(command_name, paths)
        "simplecov merge: warning — command_name #{command_name.inspect} " \
          "appears in #{paths.size} input files (#{paths.join(', ')}); " \
          "entries will be merged"
      end

      def write(path, result)
        require "fileutils"
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(result.to_hash))
      end

      def error(stderr, message)
        stderr.puts("simplecov merge: #{message}")
        1
      end
    end

    # `simplecov diff <baseline>` — print the per-file line-coverage
    # delta between coverage.json (--input) and a baseline coverage.json
    # checked in alongside the suite. Only files whose coverage moved
    # are listed; --fail-on-drop exits non-zero when any file regressed,
    # so this composes with CI as a "coverage of this PR didn't drop"
    # gate. Resolves the long-standing "diff coverage" feature request.
    module Diff
      EPSILON = 0.005 # tolerance below which a delta is considered noise

      # Per-criterion key map. coverage.json carries `lines_covered_percent`
      # plus `branches_covered_percent` / `methods_covered_percent` when
      # the corresponding criterion is enabled, so the diff can describe
      # whichever criteria the baseline + current both report on.
      CRITERIA = %i[lines branches methods].freeze
      CRITERION_FIELDS = {
        lines: {pct: "lines_covered_percent", total: "total_lines"},
        branches: {pct: "branches_covered_percent", total: "total_branches"},
        methods: {pct: "methods_covered_percent", total: "total_methods"}
      }.freeze

      STATUS_SUFFIX = {"added" => "(new file)", "removed" => "(removed)"}.freeze

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args, stderr)
        return 1 unless opts

        rows = compute_rows(opts[:current], opts[:baseline], opts[:threshold])
        rows.sort_by! { |row| row[:line_delta] }
        opts[:json] ? emit_json(stdout, rows) : emit_text(stdout, rows)
        opts[:fail_on_drop] && rows.any? { |row| row[:line_delta].negative? } ? 1 : 0
      end

      def parse(args, stderr)
        opts = {input: DEFAULT_INPUT, fail_on_drop: false, json: false, threshold: 0.0}
        rest =
          OptionParser.new do |o|
            o.on("--input PATH")         { |v| opts[:input] = v }
            o.on("--fail-on-drop")       { opts[:fail_on_drop] = true }
            o.on("--json")               { opts[:json] = true }
            o.on("--threshold N", Float) { |v| opts[:threshold] = v }
          end.parse(args)
        return stderr.puts("simplecov diff: missing baseline argument") && nil if rest.empty?

        opts[:baseline] = load_coverage(rest.first, stderr) or return nil
        opts[:current]  = load_coverage(opts[:input], stderr) or return nil
        opts
      end

      def load_coverage(path, stderr)
        return normalize_keys(JSON.parse(File.read(path)).fetch("coverage", {})) if File.exist?(path)

        stderr.puts("simplecov diff: #{path} not found")
        nil
      end

      # Strip a leading slash so coverage.json files written before the
      # `project_filename` change (keys like "/lib/foo.rb") still diff
      # cleanly against newer reports (keys like "lib/foo.rb").
      def normalize_keys(coverage)
        coverage.transform_keys { |key| key.delete_prefix("/") }
      end

      def compute_rows(current, baseline, threshold)
        files = current.keys | baseline.keys
        files.filter_map { |fname| compute_row(fname, current[fname], baseline[fname], threshold) }
      end

      def compute_row(fname, current_payload, baseline_payload, threshold)
        deltas = CRITERIA.to_h { |c| [c, pct_for(c, current_payload) - pct_for(c, baseline_payload)] }
        floor = [threshold.abs, EPSILON].max
        return nil unless deltas.values.any? { |delta| delta.abs > floor }

        {
          file: fname,
          status: status_for(current_payload, baseline_payload),
          line_delta: deltas[:lines],
          branch_delta: deltas[:branches],
          method_delta: deltas[:methods]
        }
      end

      def status_for(current_payload, baseline_payload)
        return "added"   if baseline_payload.nil?
        return "removed" if current_payload.nil?

        "changed"
      end

      def pct_for(criterion, payload)
        fields = CRITERION_FIELDS.fetch(criterion)
        return 0.0 unless payload.is_a?(Hash) && payload[fields[:total]].to_i.positive?

        payload[fields[:pct]].to_f
      end

      def emit_text(stdout, rows)
        return stdout.puts("simplecov diff: no per-file coverage changes") if rows.empty?

        rows.each { |row| stdout.puts(format_row(row)) }
      end

      def format_row(row)
        line = "  #{delta_parts(row).join('  ')}  #{row[:file]}"
        suffix = STATUS_SUFFIX[row[:status]]
        suffix ? "#{line}  #{suffix}" : line
      end

      def delta_parts(row)
        [
          format_delta(row[:line_delta], "lines"),
          (format_delta(row[:branch_delta], "branches") if row[:branch_delta].abs > EPSILON),
          (format_delta(row[:method_delta], "methods")  if row[:method_delta].abs > EPSILON)
        ].compact
      end

      def format_delta(delta, label)
        sign = delta.positive? ? "+" : ""
        format("%<sign>s%<delta>6.2f%% %<label>s", sign: sign, delta: delta, label: label)
      end

      def emit_json(stdout, rows)
        stdout.puts(JSON.pretty_generate(rows))
      end
    end

    COMMANDS = {
      "coverage" => Coverage,
      "run" => Run,
      "open" => Open,
      "report" => Report,
      "uncovered" => Uncovered,
      "merge" => Merge,
      "diff" => Diff
    }.freeze
  end
end
