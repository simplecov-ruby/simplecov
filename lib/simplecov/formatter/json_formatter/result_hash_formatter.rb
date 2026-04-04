# frozen_string_literal: true

require_relative "source_file_formatter"

module SimpleCov
  module Formatter
    class JSONFormatter
      class ResultHashFormatter
        def initialize(result)
          @result = result
        end

        def format
          format_total
          format_files
          format_groups

          formatted_result
        end

      private

        def format_total
          formatted_result[:total] = format_coverage_statistics(@result.coverage_statistics)
        end

        def format_files
          @result.files.each do |source_file|
            formatted_result[:coverage][source_file.filename] =
              format_source_file(source_file)
          end
        end

        def format_groups
          @result.groups.each do |name, file_list|
            formatted_result[:groups][name] = format_coverage_statistics(file_list.coverage_statistics)
          end
        end

        def formatted_result
          @formatted_result ||= {
            meta: {
              simplecov_version: SimpleCov::VERSION
            },
            total: {},
            coverage: {},
            groups: {}
          }
        end

        def format_source_file(source_file)
          source_file_formatter = SourceFileFormatter.new(source_file)
          source_file_formatter.format
        end

        def format_coverage_statistics(statistics)
          result = {lines: format_single_statistic(statistics[:line])}
          result[:branches] = format_single_statistic(statistics[:branch]) if SimpleCov.branch_coverage? && statistics[:branch]
          result[:methods] = format_single_statistic(statistics[:method]) if SimpleCov.method_coverage? && statistics[:method]
          result
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
