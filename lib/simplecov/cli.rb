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
      return Coverage.run(rest, stdout: stdout, stderr: stderr) if command == "coverage"
      return stdout.puts(usage) || 0 if [nil, "help", "--help", "-h"].include?(command)

      stderr.puts("simplecov: unknown command #{command.inspect}", usage)
      1
    end

    def usage
      <<~USAGE
        Usage: simplecov <command> [options]

        Commands:
          coverage <path>           Print coverage stats for the given file
          help                      Show this message

        coverage options:
          --input PATH              Read from PATH instead of #{DEFAULT_INPUT}
          --json                    Print the file's JSON entry verbatim
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
  end
end
