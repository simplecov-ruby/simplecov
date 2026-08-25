# frozen_string_literal: true

require_relative "command_helpers"
require_relative "history/output"
require_relative "../history"

module SimpleCov
  module CLI
    # `simplecov history` — the recorded coverage trend
    # (coverage/.history.json, see SimpleCov::History) in the terminal:
    # a sparkline per measured criterion with the run rows beneath, and
    # `--file PATH` for one file's trajectory instead of the totals.
    # Direction of travel is what people actually want out of a
    # coverage report; this is the report-free way to see it.
    module History
      extend CommandHelpers

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args, stderr) or return 1
        entries = load_entries(opts[:input], stderr) or return 1
        return 1 unless file_recorded?(entries, opts, stderr)

        Output.emit(stdout, opts, entries, color: SimpleCov::CLI.color_enabled?(opts, stdout))
        0
      end

      def parse(args, stderr)
        opts, rest = parse_common(args, input: default_input, file: nil) do |parser, options|
          parser.on("--file PATH") { |v| options[:file] = v }
        end
        return error_nil(stderr, "unexpected argument #{rest.first.inspect}") unless rest.empty?

        opts
      end

      # The history file, not coverage.json: this command reads the
      # sibling artifact the exit tasks append to.
      def default_input
        File.join(SimpleCov::CLI.coverage_dir, ".history.json")
      end

      def load_entries(path, stderr)
        document = JSON.parse(File.read(path))
        entries = document.dig(SimpleCov::History::ENVELOPE, "entries") if document.is_a?(Hash)
        return entries if entries.is_a?(Array)

        error_nil(stderr, "#{path} is not a SimpleCov history file")
      rescue Errno::ENOENT
        error_nil(stderr, "#{path} not found (the history is recorded automatically each time a suite reports)")
      rescue JSON::ParserError => e
        error_nil(stderr, "#{path} is not valid JSON (#{e.message.lines.first.to_s.strip})")
      rescue SystemCallError => e
        error_nil(stderr, e.message)
      end

      # A `--file` for a path no entry recorded deserves a loud answer,
      # not an empty sparkline that reads as "0% forever".
      def file_recorded?(entries, opts, stderr)
        file = opts[:file]
        return true unless file
        return true if entries.any? { |entry| entry.is_a?(Hash) && entry.dig("files", file).is_a?(Hash) }

        error(stderr, "no recorded coverage for #{file} in #{opts[:input]}")
        false
      end
    end
  end
end
