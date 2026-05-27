# frozen_string_literal: true

require "json"
require "optparse"

module SimpleCov
  module CLI
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

        if opts[:json]
          emit_json(stdout, data)
        else
          emit_text(stdout, data, SimpleCov::CLI.color_enabled?(opts, stdout))
        end
        0
      end

      def parse(args)
        opts = {input: SimpleCov::CLI.default_input, json: false, no_color: false}
        OptionParser.new do |o|
          o.on("--input PATH") { |v| opts[:input] = v }
          o.on("--json")       { opts[:json] = true }
          o.on("--no-color")   { opts[:no_color] = true }
        end.parse(args)
        opts
      end

      def load_data(input, stderr)
        return JSON.parse(File.read(input)) if File.exist?(input)

        stderr.puts("simplecov report: #{input} not found")
        nil
      end

      def emit_text(stdout, data, color)
        emit_totals(stdout, "All Files", data.fetch("total", {}), color)
        data.fetch("groups", {}).each { |name, group| emit_totals(stdout, name, group, color) }
      end

      def emit_totals(stdout, label, totals, color)
        stdout.puts(label)
        SECTIONS.each { |display, key| emit_section(stdout, display, totals[key], color) }
        stdout.puts
      end

      def emit_section(stdout, display, section, color)
        return unless section.is_a?(Hash) && section["total"].to_i.positive?

        stdout.puts(format("  %<label>-7s %<pct>s (%<covered>d / %<total>d)",
                           label: "#{display}:",
                           pct: SimpleCov::Color.colorize_percent(section["percent"].to_f, enabled: color),
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
  end
end
