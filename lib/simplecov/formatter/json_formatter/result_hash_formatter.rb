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
          format_errors

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

        def format_errors
          format_minimum_coverage_errors
          format_minimum_coverage_by_file_errors
          format_minimum_coverage_by_group_errors
          format_maximum_coverage_drop_errors
        end

        CRITERION_KEYS = {line: :lines, branch: :branches, method: :methods}.freeze
        private_constant :CRITERION_KEYS

        def format_minimum_coverage_errors
          SimpleCov::CoverageViolations.minimum_overall(@result, SimpleCov.minimum_coverage).each do |violation|
            key = CRITERION_KEYS.fetch(violation.fetch(:criterion))
            bucket = formatted_result[:errors][:minimum_coverage] ||= {}
            bucket[key] = {expected: violation.fetch(:expected), actual: violation.fetch(:actual)}
          end
        end

        def format_minimum_coverage_by_file_errors
          SimpleCov::CoverageViolations.minimum_by_file(@result, SimpleCov.minimum_coverage_by_file).each do |violation|
            key = CRITERION_KEYS.fetch(violation.fetch(:criterion))
            bucket = formatted_result[:errors][:minimum_coverage_by_file] ||= {}
            criterion_errors = bucket[key] ||= {}
            criterion_errors[violation.fetch(:filename)] = {expected: violation.fetch(:expected), actual: violation.fetch(:actual)}
          end
        end

        def format_minimum_coverage_by_group_errors
          SimpleCov::CoverageViolations.minimum_by_group(@result, SimpleCov.minimum_coverage_by_group).each do |violation|
            key = CRITERION_KEYS.fetch(violation.fetch(:criterion))
            bucket = formatted_result[:errors][:minimum_coverage_by_group] ||= {}
            group_errors = bucket[violation.fetch(:group_name)] ||= {}
            group_errors[key] = {expected: violation.fetch(:expected), actual: violation.fetch(:actual)}
          end
        end

        def format_maximum_coverage_drop_errors
          SimpleCov::CoverageViolations.maximum_drop(@result, SimpleCov.maximum_coverage_drop).each do |violation|
            key = CRITERION_KEYS.fetch(violation.fetch(:criterion))
            bucket = formatted_result[:errors][:maximum_coverage_drop] ||= {}
            bucket[key] = {maximum: violation.fetch(:maximum), actual: violation.fetch(:actual)}
          end
        end

        def formatted_result
          @formatted_result ||= {
            meta: {
              simplecov_version: SimpleCov::VERSION
            },
            total: {},
            coverage: {},
            groups: {},
            errors: {}
          }
        end

        def format_source_file(source_file)
          source_file_formatter = SourceFileFormatter.new(source_file)
          source_file_formatter.format
        end

        def format_coverage_statistics(statistics)
          result = {lines: format_line_statistic(statistics[:line])}
          result[:branches] = format_single_statistic(statistics[:branch]) if SimpleCov.branch_coverage? && statistics[:branch]
          result[:methods] = format_single_statistic(statistics[:method]) if SimpleCov.method_coverage? && statistics[:method]
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
