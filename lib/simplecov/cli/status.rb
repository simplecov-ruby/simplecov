# frozen_string_literal: true

require "json"
require "optparse"
require "time"
require_relative "command_helpers"
require_relative "git"
require_relative "status/facts"

module SimpleCov
  module CLI
    # `simplecov status` — the freshness diagnostic: how old the report
    # is, which commit it reflects and how far HEAD has moved since,
    # what it measured, whether a test map was recorded, and what the
    # resultset holds. The metadata has been in the artifacts all
    # along; this reads it aloud, so every staleness question the other
    # commands raise has a one-command answer.
    module Status
      extend CommandHelpers

    module_function

      def run(args, stdout:, stderr:)
        opts, = parse_common(args)
        document = CoverageFile.load_document(opts[:input], command: "status", stderr: stderr)
        return 1 unless document

        facts = Facts.gather(document, SimpleCov::CLI.default_resultset)
        opts[:json] ? stdout.puts(JSON.pretty_generate(facts)) : print_facts(facts, opts, stdout)
        0
      end

      def print_facts(facts, opts, stdout)
        stdout.puts("report #{opts[:input]}")
        report_lines(facts).each { |line| stdout.puts("  #{line}") }
        print_resultset(facts, stdout)
      end

      def report_lines(facts)
        [
          facts[:generated_at] && "generated #{facts[:generated_at]}#{age_suffix(facts[:age])}",
          provenance_words(facts),
          "commit #{commit_words(facts)}",
          facts[:totals].empty? ? nil : totals_words(facts[:totals]),
          "tests recorded: #{contexts_words(facts[:contexts])}"
        ].compact
      end

      def provenance_words(facts)
        "by simplecov #{facts[:version]} running #{facts[:command_name]}"
      end

      def commit_words(facts)
        commit = facts[:commit]
        return "not recorded" unless commit.is_a?(String)

        "#{commit[0, 7]} (#{distance_words(facts[:behind])})"
      end

      def distance_words(behind)
        return "not in this repository's history" unless behind
        return "current HEAD" if behind.zero?

        "#{behind} commit#{'s' unless behind == 1} behind HEAD"
      end

      def totals_words(totals)
        totals.map { |name, percent| "#{name} #{format('%.2f%%', percent)}" }.join(", ")
      end

      def contexts_words(count)
        count ? "#{count} (track_tests)" : "none (enable track_tests to select and re-run by test)"
      end

      def print_resultset(facts, stdout)
        entries = facts[:resultset]
        return stdout.puts("resultset none") unless entries

        stdout.puts("resultset #{facts[:resultset_path]}")
        entries.each do |entry|
          age = entry[:age] ? "#{age_in_words(entry[:age])} ago" : "age unknown"
          stdout.puts("  #{entry[:command]}: #{age}")
        end
      end

      def age_suffix(age)
        age ? " (#{age_in_words(age)} ago)" : ""
      end

      def age_in_words(seconds)
        return "#{seconds.round} seconds" if seconds < 90
        return "#{(seconds / 60.0).round} minutes" if seconds < 5400
        return "#{(seconds / 3600.0).round} hours" if seconds < 129_600

        "#{(seconds / 86_400.0).round} days"
      end
    end
  end
end
