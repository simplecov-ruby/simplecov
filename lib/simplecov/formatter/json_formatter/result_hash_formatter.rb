# frozen_string_literal: true

require "open3"
require "time"
require_relative "errors_formatter"
require_relative "production_section_formatter"
require_relative "source_file_formatter"

module SimpleCov
  module Formatter
    class JSONFormatter
      class ResultHashFormatter
        # Bump this (and SCHEMA_URL) when the JSON shape changes: additive changes
        # bump the minor segment, removals or shape changes the major. The versioned
        # file at schemas/coverage-vX.Y.schema.json is the canonical artifact
        # consumers should pin to.
        SCHEMA_VERSION = "1.3"
        SCHEMA_URL = "https://raw.githubusercontent.com/simplecov-ruby/simplecov/main/schemas/coverage-v#{SCHEMA_VERSION}.schema.json".freeze
        private_constant :SCHEMA_VERSION, :SCHEMA_URL

        class << self
          def format(result, include_source: true)
            document = {
              :$schema => SCHEMA_URL,
              :meta => format_meta(result),
              :total => format_coverage_statistics(result.coverage_statistics),
              :coverage => format_files(result, include_source: include_source),
              :groups => format_groups(result),
              :errors => ErrorsFormatter.call(result)
            }
            add_optional_sections(document, result)
            document
          end

        private

          # Contexts are present exactly when the result carried a complete map, so
          # consumers can tell "recorded and empty" from "not recorded". History is
          # present only when past runs are recorded, since one point is not a trend,
          # and production coverage only when a store is configured and readable.
          def add_optional_sections(document, result)
            document[:contexts] = result.contexts.contexts if result.contexts
            history = History.entries_with(result)
            document[:history] = history if history.length > 1
            production = ProductionSectionFormatter.call
            document[:production] = production if production
          end

          def format_files(result, include_source:)
            result.files.to_h do |source_file|
              [source_file.project_filename,
               SourceFileFormatter.call(source_file, include_source: include_source, contexts: result.contexts)]
            end
          end

          def format_groups(result)
            result.groups.to_h do |name, file_list|
              stats = format_coverage_statistics(file_list.coverage_statistics)
              [name, stats.merge(files: file_list.map(&:project_filename))]
            end
          end

          def format_meta(result)
            {
              schema_version: SCHEMA_VERSION,
              simplecov_version: VERSION,
              command_name: result.command_name, command_names: result.command_names,
              project_name: SimpleCov.project_name,
              timestamp: result.created_at.iso8601(3),
              root: SimpleCov.root,
              commit: git_commit,
              primary_coverage: SimpleCov.primary_coverage.to_s, **coverage_flags
            }
          end

          # Recorded so tools can recover the exact source a report was generated
          # against, which matters most when `source_in_json false` drops the source
          # text. stderr is captured rather than forwarded so a non-git project doesn't
          # print git's diagnostics to the build.
          def git_commit
            output, status = Open3.capture2e("git", "-C", SimpleCov.root, "rev-parse", "HEAD")
            output.strip if status.success?
          rescue StandardError
            nil
          end

          def coverage_flags
            {
              line_coverage: SimpleCov.line_coverage?,
              branch_coverage: SimpleCov.branch_coverage?,
              method_coverage: SimpleCov.method_coverage?
            }
          end

          # A criterion the run did not measure is absent from `statistics` entirely,
          # and gets no section.
          def format_coverage_statistics(statistics)
            result = {} #: Hash[Symbol, untyped]
            line = statistics[:line]
            branch = statistics[:branch]
            method_stat = statistics[:method]
            result[:lines]    = format_line_statistic(line)          if line
            result[:branches] = format_single_statistic(branch)      if branch
            result[:methods]  = format_single_statistic(method_stat) if method_stat
            result
          end

          def format_line_statistic(stat)
            {
              covered: stat.covered,
              missed: stat.missed,
              omitted: stat.omitted,
              total: stat.total,
              percent: stat.percent,
              strength: stat.strength
            }
          end

          def format_single_statistic(stat)
            {
              covered: stat.covered,
              missed: stat.missed,
              total: stat.total,
              percent: stat.percent,
              strength: stat.strength
            }
          end
        end
      end
    end
  end
end
