# frozen_string_literal: true

require "time"
require_relative "errors_formatter"
require_relative "source_file_formatter"

module SimpleCov
  module Formatter
    class JSONFormatter
      # Builds the hash that JSONFormatter serializes to coverage.json:
      # meta, per-file coverage data, group totals, and aggregate stats.
      class ResultHashFormatter
        def initialize(result)
          @result = result
        end

        def format
          {
            meta: format_meta,
            total: format_coverage_statistics(@result.coverage_statistics),
            coverage: format_files,
            groups: format_groups,
            errors: ErrorsFormatter.new(@result).call
          }
        end

      private

        def format_files
          @result.files.to_h { |source_file| [source_file.project_filename, SourceFileFormatter.new(source_file).call] }
        end

        def format_groups
          @result.groups.to_h do |name, file_list|
            stats = format_coverage_statistics(file_list.coverage_statistics)
            [name, stats.merge(files: file_list.map(&:project_filename))]
          end
        end

        def format_meta
          {
            simplecov_version: SimpleCov::VERSION,
            command_name: @result.command_name,
            project_name: SimpleCov.project_name,
            timestamp: @result.created_at.iso8601(3),
            root: SimpleCov.root,
            branch_coverage: SimpleCov.branch_coverage?,
            method_coverage: SimpleCov.method_coverage?
          }
        end

        def format_coverage_statistics(statistics)
          result = {}
          result[:lines]    = format_line_statistic(statistics[:line])      if statistics[:line]
          result[:branches] = format_single_statistic(statistics[:branch])  if statistics[:branch]
          result[:methods]  = format_single_statistic(statistics[:method])  if statistics[:method]
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
