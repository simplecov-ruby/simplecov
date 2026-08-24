# frozen_string_literal: true

module SimpleCov
  module CLI
    module Status
      # Gathers the freshness facts from the artifacts: the report's
      # metadata, how far HEAD has moved since it was generated, and
      # the resultset's entries with their ages.
      module Facts
      module_function

        def gather(document, resultset_path)
          meta_facts(document).merge(
            totals: totals(document["total"]),
            contexts: document["contexts"].is_a?(Array) ? document["contexts"].size : nil,
            resultset_path: resultset_path, resultset: resultset(resultset_path)
          )
        end

        def meta_facts(document)
          none = {} #: Hash[String, untyped]
          meta = document["meta"].is_a?(Hash) ? document["meta"] : none
          generated = parse_time(meta["timestamp"])
          {
            generated_at: meta["timestamp"], age: generated && (Time.now - generated).to_i,
            version: meta["simplecov_version"], command_name: meta["command_name"],
            commit: meta["commit"], behind: behind(meta["commit"])
          }
        end

        def parse_time(value)
          value.is_a?(String) ? Time.iso8601(value) : nil
        rescue ArgumentError
          nil
        end

        # Commits between the report's commit and HEAD: 0 at HEAD, nil
        # when unanswerable (no commit recorded, no git, or a commit
        # this repository has never seen).
        def behind(commit)
          return nil unless commit.is_a?(String)

          stdout, _detail, success = Git.capture("rev-list", "--count", "#{commit}..HEAD")
          success ? Integer((_ = stdout).strip, 10) : nil
        end

        def totals(total)
          return {} unless total.is_a?(Hash)

          rows = {"line" => "lines", "branch" => "branches", "method" => "methods"}.filter_map do |name, key|
            percent = total.dig(key, "percent")
            [name, percent] if percent.is_a?(Numeric)
          end
          rows.to_h
        end

        # The resultset's entries with their ages, nil when there is no
        # readable resultset — its absence is a fact, not an error.
        def resultset(path)
          parsed = JSON.parse(File.read(path))
          return nil unless parsed.is_a?(Hash)

          parsed.map do |command, data|
            timestamp = data.is_a?(Hash) ? data["timestamp"] : nil
            {command: command, age: timestamp.is_a?(Numeric) ? (Time.now - Time.at(timestamp)).to_i : nil}
          end
        rescue SystemCallError, JSON::ParserError
          nil
        end
      end
    end
  end
end
