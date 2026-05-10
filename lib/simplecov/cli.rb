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
          open                      Open the HTML report in the default browser
          help                      Show this message

        coverage / report / uncovered options:
          --input PATH              Read from PATH instead of #{DEFAULT_INPUT}

        coverage options:
          --json                    Print the file's JSON entry verbatim

        report options:
          --json                    Emit totals and group sections as JSON

        uncovered options:
          --threshold N             Only show files below N% line coverage
          --top N                   Show at most N files (default: 10)
          --json                    Emit results as a JSON array (for CI)

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

    COMMANDS = {
      "coverage" => Coverage,
      "run" => Run,
      "open" => Open,
      "report" => Report,
      "uncovered" => Uncovered
    }.freeze
  end
end
