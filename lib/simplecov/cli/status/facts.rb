# frozen_string_literal: true

module SimpleCov
  module CLI
    module Status
      module Facts
        extend self

        def gather(document, resultset_path)
          contexts = document["contexts"]
          meta_facts(document).merge(
            totals: totals(document["total"]),
            contexts: (contexts.size if contexts.instance_of?(Array)),
            resultset_path: resultset_path, resultset: resultset(resultset_path)
          )
        end

        def meta_facts(document)
          none = {} #: Hash[String, untyped]
          recorded = document["meta"]
          meta = recorded.instance_of?(Hash) ? recorded : none
          generated = parse_time(meta["timestamp"])
          {
            generated_at: meta["timestamp"], age: generated && whole_seconds(Time.now - generated),
            version: meta["simplecov_version"], command_name: meta["command_name"],
            commit: meta["commit"], behind: behind(meta["commit"])
          }
        end

        def age_of(timestamp)
          whole_seconds(Process.clock_gettime(Process::CLOCK_REALTIME) - timestamp)
        end

        def whole_seconds(elapsed)
          elapsed.truncate
        end

        def parse_time(value)
          Time.iso8601(value) if value.instance_of?(String)
        rescue ArgumentError
          nil
        end

        # Commits between the report's commit and HEAD: 0 at HEAD, nil when
        # unanswerable, meaning no commit recorded, no git, or a commit this
        # repository has never seen.
        def behind(commit)
          return nil unless commit.instance_of?(String)

          stdout, _detail, success = Git.capture("rev-list", "--count", "#{commit}..HEAD")
          commit_count(_ = stdout) if success
        end

        # `Integer` ignores surrounding whitespace on its own, so git's trailing
        # newline needs no trimming. The base is spelled out because bare `Integer`
        # reads a leading zero as octal.
        def commit_count(output)
          Integer(output, 10)
        end

        def totals(total)
          return {} unless total.instance_of?(Hash)

          rows = {"line" => "lines", "branch" => "branches", "method" => "methods"}.filter_map do |name, key|
            percent = total.dig(key, "percent")
            [name, percent] if percent.is_a?(Numeric)
          end
          rows.to_h
        end

        # nil when there is no readable resultset: its absence is a fact, not an
        # error.
        def resultset(path)
          parsed = JSON.parse(File.read(path))
          return nil unless parsed.instance_of?(Hash)

          parsed.map do |command, data|
            timestamp = data["timestamp"] if data.instance_of?(Hash)
            {command: command, age: (age_of(timestamp) if timestamp.is_a?(Numeric))}
          end
        rescue SystemCallError, JSON::ParserError
          nil
        end
      end
    end
  end
end
