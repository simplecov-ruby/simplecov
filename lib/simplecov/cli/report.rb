# frozen_string_literal: true

require "json"
require "optparse"
require_relative "command_helpers"

module SimpleCov
  module CLI
    # `simplecov report [--input PATH]` — pretty-print the overall
    # totals row plus per-group totals from a JSONFormatter
    # coverage.json. Same numbers as the HTML report's totals row, for
    # contexts where opening a browser isn't an option (CI logs, ssh
    # sessions, terminal-only workflows).
    module Report
      extend CommandHelpers

      TOTAL_LABEL = "All Files"
      SECTIONS = [%w[Line lines], %w[Branch branches], %w[Method methods]].freeze

    module_function

      def run(args, stdout:, stderr:)
        opts = parse(args)
        return 1 unless (data = load_data(opts[:input], stderr))

        if opts[:json]
          emit_json(stdout, data)
        else
          emit_text(stdout, data, SimpleCov::CLI.color_enabled?(opts, stdout))
        end
        0
      end

      def parse(args)
        opts = {input: SimpleCov::CLI.default_input, json: false, no_color: false}
        OptionParser.new { |o| common_options(o, opts) }.parse(args)
        opts
      end

      def load_data(input, stderr)
        CoverageFile.load_document(input, command: "report", stderr: stderr)
      end

      def emit_text(stdout, data, color)
        none = {} #: Hash[String, untyped]
        emit_totals(stdout, TOTAL_LABEL, data.fetch("total", none), color)
        data.fetch("groups", none).each do |name, group|
          label = name == TOTAL_LABEL ? "#{name} (group)" : name
          emit_totals(stdout, label, group, color)
        end
      end

      def emit_totals(stdout, label, totals, color)
        stdout.puts(label)
        SECTIONS.each { |display, key| emit_section(stdout, display, totals[key], color) }
        stdout.puts
      end

      def emit_section(stdout, display, section, color)
        return unless section.is_a?(Hash) && section["total"].to_i.positive?

        stdout.puts(stats_row(display,
                              SimpleCov::Color.colorize_percent(section["percent"].to_f, enabled: color),
                              section["covered"],
                              section["total"]))
      end

      def emit_json(stdout, data)
        none = {} #: Hash[String, untyped]
        groups = data.fetch("groups", none).transform_values { |group| collect_section(group) }
        payload = {"total" => collect_section(data.fetch("total", none)), "groups" => groups}
        stdout.puts(JSON.pretty_generate(payload))
      end

      def collect_section(totals)
        sections = {} #: Hash[String, untyped]
        SECTIONS.each_with_object(sections) do |(_, key), out|
          section = totals[key]
          next unless section.is_a?(Hash) && section["total"].to_i.positive?

          out[key.to_s] = {
            "percent" => section["percent"], "covered" => section["covered"], "total" => section["total"]
          }
        end
      end
    end
  end
end
