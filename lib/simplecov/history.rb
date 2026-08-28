# frozen_string_literal: true

require "json"
require "open3"
require "time"
require_relative "atomic_file"

module SimpleCov
  # A bounded record of past runs, coverage/.history.json (see #1267):
  # one entry per reported run carrying the per-criterion totals, the
  # per-group and per-file percentages, a timestamp, and the branch and
  # commit when the project is a git checkout. `.last_run.json` keeps
  # its one-number-per-criterion job untouched; the history is what
  # turns "did the number move since the very last run" into direction
  # of travel: `simplecov history` in the terminal, and drop checks
  # against a median or the same branch instead of against whatever
  # happened to run most recently.
  #
  # Entries are capped (`history_limit`, 100 by default) and written
  # atomically, and a corrupt or foreign file degrades to an empty
  # history with a warning rather than crashing the at_exit hook, the
  # same tolerance `.last_run.json` has. The file is deliberately plain
  # committable JSON, so a project that wants its trend to survive a
  # clean CI checkout can check it in.
  module History
    ENVELOPE = "simplecov_history"
    FORMAT_VERSION = 1

    class << self
      def history_path
        File.join(SimpleCov.coverage_path, ".history.json")
      end

      # Append the run to the history, keeping the newest
      # `history_limit` entries. A limit of 0 disables recording.
      def record(result)
        limit = SimpleCov.history_limit
        return if limit.zero?

        entries = read
        entries << entry_for(result)
        write(entries.last(limit))
      end

      # The recorded entries, oldest first. Empty for a missing file;
      # empty with a warning for one that cannot be read as a history.
      def read
        return [] unless File.exist?(history_path)

        content = File.read(history_path)
        return [] if content.match?(/\A\s*\z/)

        # JSON answers plain arrays and hashes, never a subclass of one,
        # so the shape check asks about the class itself.
        entries = JSON.parse(content).dig(ENVELOPE, "entries")
        entries.instance_of?(Array) ? entries : invalid_history
      rescue JSON::ParserError
        invalid_history
      end

      # The recorded entries plus `result` as the newest, capped, and
      # without writing anything: what the report artifacts embed, so
      # the embedded history includes the run being reported even
      # though recording happens later (after the exit checks pass).
      def entries_with(result)
        (read << entry_for(result)).last(SimpleCov.history_limit)
      end

      # ["branch", "sha"], each nil when unanswerable (not a checkout,
      # no git on PATH). A detached HEAD reports its branch as nil
      # rather than the literal "HEAD" most CI checkouts would record.
      def git_info
        branch = git("rev-parse", "--abbrev-ref", "HEAD")
        branch = nil if branch.eql?("HEAD")
        [branch, git("rev-parse", "HEAD")]
      end

    private

      def entry_for(result)
        branch, commit = git_info
        {
          # getutc, not utc: the destructive variant would rezone the
          # Time the result (and the meta timestamp) still holds.
          "created_at" => result.created_at.getutc.iso8601,
          "branch" => branch,
          "commit" => commit,
          "totals" => measured_percents(result),
          "groups" => result.groups.transform_values { |files| measured_percents(files) },
          "files" => files_percents(result)
        }
      end

      # {criterion => percent} in `.last_run.json`'s singular-key
      # vocabulary. Result and FileList statistics already carry only
      # the criteria the run measured (see
      # FileList#coverage_statistics), so no filtering happens here.
      def measured_percents(stats_source)
        stats_source.coverage_statistics.to_h do |criterion, stats|
          [criterion.to_s, SimpleCov.round_coverage(stats.percent)]
        end
      end

      # Per-file percents in the same {criterion => percent} shape the
      # totals and groups use, covering every measured criterion.
      def files_percents(result)
        measured = result.coverage_statistics
        initial = {} #: Hash[String, Hash[String, Numeric]]
        result.files.each_with_object(initial) do |file, percents|
          # fetch: a SourceFile's statistics carry every criterion, so a
          # missing measured key is an invariant break worth raising on.
          stats = file.coverage_statistics
          percents[file.project_filename] = measured.to_h do |criterion, _run_total|
            [criterion.to_s, SimpleCov.round_coverage(stats.fetch(criterion).percent)]
          end
        end
      end

      def write(entries)
        payload = {ENVELOPE => {"format_version" => FORMAT_VERSION, "entries" => entries}}
        AtomicFile.write(history_path, "#{JSON.pretty_generate(payload)}\n")
      end

      def invalid_history
        warn "[SimpleCov]: Warning! Parsing JSON content of .history.json failed, starting a fresh history"
        []
      end

      # A root that is not a String (a Pathname, say) is still a path,
      # and git's own answers carry a trailing newline and nothing else.
      def git(*)
        output, status = Open3.capture2e("git", "-C", SimpleCov.root.to_s, *)
        output.rstrip if status.success?
      rescue StandardError
        nil
      end
    end
  end
end
