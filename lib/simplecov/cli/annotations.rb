# frozen_string_literal: true

require "digest"
require "json"

module SimpleCov
  module CLI
    # The `--annotate KIND` output shared by `uncovered` and `patch`: each command
    # reduces its answer to diagnostics (a path, a contiguous missed line range,
    # and the criterion that missed), and one emitter per CI host renders them in
    # that host's native inline-annotation channel, so a gap surfaces on the diff
    # with no upload step and no extra gem.
    module Annotations
      KINDS = %w[github gitlab rdjson azure teamcity buildkite].freeze

      MESSAGES = {
        line: "Not covered by tests",
        branch: "Branch not covered by tests",
        method: "Method not covered by tests"
      }.freeze

      DESCRIPTIONS = {
        line: "Lines the tests never executed",
        branch: "Branches the tests never took",
        method: "Methods the tests never called"
      }.freeze

      SOURCE = {"name" => "simplecov", "url" => "https://github.com/simplecov-ruby/simplecov"}.freeze

      # TeamCity's service message grammar and Azure's logging command grammar
      # each reserve a few characters in attribute values.
      TEAMCITY_ESCAPES = {"|" => "||", "'" => "|'", "[" => "|[", "]" => "|]", "\n" => "|n", "\r" => "|r"}.freeze
      AZURE_ESCAPES = {"%" => "%AZP25", ";" => "%3B", "]" => "%5D", "\n" => "%0A", "\r" => "%0D"}.freeze

      extend self

      def issue(opts)
        kind = opts.fetch(:annotate)
        return nil unless kind
        return "unknown --annotate #{kind.inspect} (expected #{expected_kinds})" unless KINDS.include?(kind)

        "cannot combine --annotate with --json" if opts.fetch(:json)
      end

      def expected_kinds
        *rest, last = KINDS
        "#{rest.join(", ")}, or #{last}"
      end

      def diagnostics(path, missed, criterion)
        missed.slice_when { |previous, current| current > previous + 1 }.map do |run|
          {path: path, first: run.first, last: run.last, criterion: criterion, message: MESSAGES.fetch(criterion)}
        end
      end

      def emit(stdout, kind, diagnostics)
        case kind
        when "github" then github(stdout, diagnostics)
        when "gitlab" then stdout.puts(JSON.pretty_generate(gitlab(diagnostics)))
        when "rdjson" then stdout.puts(JSON.pretty_generate(rdjson(diagnostics)))
        when "azure" then azure(stdout, diagnostics)
        when "teamcity" then teamcity(stdout, diagnostics)
        else buildkite(stdout, diagnostics)
        end
      end

      def github(stdout, diagnostics)
        diagnostics.each do |diagnostic|
          stdout.puts("::warning file=#{diagnostic.fetch(:path)},line=#{diagnostic.fetch(:first)}," \
                      "endLine=#{diagnostic.fetch(:last)}::#{diagnostic.fetch(:message)}")
        end
      end

      # GitLab's Code Quality report, a subset of the Code Climate spec, read from
      # a `codequality` artifact for merge request annotations.
      def gitlab(diagnostics)
        diagnostics.map do |diagnostic|
          {
            "description" => diagnostic.fetch(:message),
            "check_name" => "coverage",
            "fingerprint" => fingerprint(diagnostic),
            "severity" => "minor",
            "location" => {
              "path" => diagnostic.fetch(:path),
              "lines" => {"begin" => diagnostic.fetch(:first), "end" => diagnostic.fetch(:last)}
            }
          }
        end
      end

      def fingerprint(diagnostic)
        Digest::SHA256.hexdigest("#{diagnostic.fetch(:path)}:#{diagnostic.fetch(:first)}-#{diagnostic.fetch(:last)}:" \
                                 "#{diagnostic.fetch(:criterion)}")
      end

      # reviewdog's Diagnostic Format, which reviewdog posts to whichever host it
      # runs under.
      def rdjson(diagnostics)
        {"source" => SOURCE, "severity" => "WARNING", "diagnostics" => diagnostics.map { |d| rdjson_diagnostic(d) }}
      end

      def rdjson_diagnostic(diagnostic)
        {
          "message" => diagnostic.fetch(:message),
          "location" => {
            "path" => diagnostic.fetch(:path),
            "range" => {"start" => {"line" => diagnostic.fetch(:first)}, "end" => {"line" => diagnostic.fetch(:last)}}
          },
          "severity" => "WARNING",
          "code" => {"value" => diagnostic.fetch(:criterion).to_s}
        }
      end

      # Azure Pipelines logging commands carry one line number, so a range is
      # spelled out in the message.
      def azure(stdout, diagnostics)
        diagnostics.each do |diagnostic|
          stdout.puts("##vso[task.logissue type=warning;sourcepath=#{escape(diagnostic.fetch(:path), AZURE_ESCAPES)};" \
                      "linenumber=#{diagnostic.fetch(:first)}]#{described(diagnostic)}")
        end
      end

      # TeamCity's code inspection service messages: each criterion is one
      # inspection type, declared once before its first inspection.
      def teamcity(stdout, diagnostics)
        diagnostics.group_by { |diagnostic| diagnostic.fetch(:criterion) }.each do |criterion, group|
          id = "simplecov.#{criterion}"
          stdout.puts(service_message("inspectionType", id: id, name: MESSAGES.fetch(criterion),
            description: DESCRIPTIONS.fetch(criterion), category: "Code coverage"))
          group.each do |diagnostic|
            stdout.puts(service_message("inspection", typeId: id, message: described(diagnostic),
              file: diagnostic.fetch(:path), line: diagnostic.fetch(:first), SEVERITY: "WARNING"))
          end
        end
      end

      def service_message(name, attributes)
        body = attributes.map { |key, value| "#{key}='#{escape(value.to_s, TEAMCITY_ESCAPES)}'" }.join(" ")
        "##teamcity[#{name} #{body}]"
      end

      # Buildkite has no per-line channel; its annotations are Markdown, so this
      # is the body for `buildkite-agent annotate`.
      def buildkite(stdout, diagnostics)
        sections = diagnostics.group_by { |diagnostic| diagnostic.fetch(:message) }.map do |message, group|
          (["#### #{message}"] + group.map { |diagnostic| "- `#{diagnostic.fetch(:path)}:#{range(diagnostic)}`" }).join("\n")
        end
        stdout.puts(sections.join("\n\n")) unless sections.empty?
      end

      def described(diagnostic)
        return diagnostic.fetch(:message) if diagnostic.fetch(:first).equal?(diagnostic.fetch(:last))

        "#{diagnostic.fetch(:message)} (lines #{range(diagnostic)})"
      end

      def range(diagnostic)
        [diagnostic.fetch(:first), diagnostic.fetch(:last)].uniq.join("-")
      end

      def escape(text, escapes)
        text.gsub(Regexp.union(escapes.keys), escapes)
      end
    end
  end
end
