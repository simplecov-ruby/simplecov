# frozen_string_literal: true

require_relative "command_helpers"
require_relative "history/output"
require_relative "../history"

module SimpleCov
  module CLI
    # `simplecov history`: the recorded coverage trend in the terminal, a
    # sparkline per measured criterion with the run rows beneath, and
    # `--file PATH` for one file's trajectory instead of the totals.
    module History
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:, **)
        opts = parse(args, stderr) or return 1
        entries = load_entries(opts.fetch(:input), stderr) or return 1
        return 1 unless file_recorded?(entries, opts, stderr)

        Output.emit(stdout, opts, entries, color: CLI.color_enabled?(opts, stdout))
        0
      end

      def parse(args, stderr)
        opts, rest = parse_common(args, input: default_input, file: nil) do |parser, options|
          parser.on("--file PATH") { |v| options[:file] = v }
        end
        return error_nil(stderr, "unexpected argument #{rest.first.inspect}") unless rest.empty?

        opts
      end

      # The history file, not coverage.json: this command reads the sibling
      # artifact the exit tasks append to.
      def default_input
        File.join(CLI.coverage_dir, ".history.json")
      end

      def load_entries(path, stderr)
        document = JSON.parse(File.read(path))
        entries = document.dig(SimpleCov::History::ENVELOPE, "entries") if document.instance_of?(Hash)
        return entries if entries.instance_of?(Array)

        error_nil(stderr, "#{path} is not a SimpleCov history file")
      rescue Errno::ENOENT
        error_nil(stderr, "#{path} not found (the history is recorded automatically each time a suite reports)")
      rescue JSON::ParserError => e
        error_nil(stderr, "#{path} is not valid JSON (#{e.message.lines.first.to_s.strip})")
      rescue SystemCallError => e
        error_nil(stderr, "#{path} could not be read (#{e})")
      end

      # A `--file` for a path no entry recorded deserves a loud answer, not an
      # empty sparkline that reads as "0% forever".
      def file_recorded?(entries, opts, stderr)
        file = opts.fetch(:file)
        return true unless file
        return true if entries.any? { |entry| entry.instance_of?(Hash) && entry.dig("files", file).instance_of?(Hash) }

        error(stderr, "no recorded coverage for #{file} in #{opts.fetch(:input)}")
        false
      end
    end
  end
end
