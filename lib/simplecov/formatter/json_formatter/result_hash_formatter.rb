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
          SimpleCov.minimum_coverage.each do |criterion, expected_percent|
            actual = @result.coverage_statistics.fetch(criterion).percent
            next unless actual < expected_percent

            key = CRITERION_KEYS.fetch(criterion)
            minimum_coverage = formatted_result[:errors][:minimum_coverage] ||= {}
            minimum_coverage[key] = {expected: expected_percent, actual: actual}
          end
        end

        def format_minimum_coverage_by_file_errors
          SimpleCov.minimum_coverage_by_file.each do |criterion, expected_percent|
            @result.files.each do |file|
              actual = SimpleCov.round_coverage(file.coverage_statistics.fetch(criterion).percent)
              next unless actual < expected_percent

              key = CRITERION_KEYS.fetch(criterion)
              by_file = formatted_result[:errors][:minimum_coverage_by_file] ||= {}
              criterion_errors = by_file[key] ||= {}
              criterion_errors[file.filename] = {expected: expected_percent, actual: actual}
            end
          end
        end

        def format_minimum_coverage_by_group_errors
          SimpleCov.minimum_coverage_by_group.each do |group_name, minimum_group_coverage|
            group = @result.groups[group_name]
            next unless group

            minimum_group_coverage.each do |criterion, expected_percent|
              actual = SimpleCov.round_coverage(group.coverage_statistics.fetch(criterion).percent)
              next unless actual < expected_percent

              key = CRITERION_KEYS.fetch(criterion)
              by_group = formatted_result[:errors][:minimum_coverage_by_group] ||= {}
              group_errors = by_group[group_name] ||= {}
              group_errors[key] = {expected: expected_percent, actual: actual}
            end
          end
        end

        def format_maximum_coverage_drop_errors
          return if SimpleCov.maximum_coverage_drop.empty?

          last_run = SimpleCov::LastRun.read
          return unless last_run

          SimpleCov.maximum_coverage_drop.each do |criterion, max_drop|
            drop = coverage_drop_for(criterion, last_run)
            next unless drop && drop > max_drop

            key = CRITERION_KEYS.fetch(criterion)
            coverage_drop = formatted_result[:errors][:maximum_coverage_drop] ||= {}
            coverage_drop[key] = {maximum: max_drop, actual: drop}
          end
        end

        def coverage_drop_for(criterion, last_run)
          last_coverage_percent = last_run.dig(:result, criterion)
          last_coverage_percent ||= last_run.dig(:result, :covered_percent) if criterion == :line
          return nil unless last_coverage_percent

          current = SimpleCov.round_coverage(@result.coverage_statistics.fetch(criterion).percent)
          (last_coverage_percent - current).floor(10)
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
