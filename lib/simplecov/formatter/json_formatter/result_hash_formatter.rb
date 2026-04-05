# frozen_string_literal: true

require "time"

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
            group_data = format_coverage_statistics(file_list.coverage_statistics)
            group_data[:files] = file_list.map(&:filename)
            formatted_result[:groups][name] = group_data
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
          @formatted_result ||= {meta: format_meta, total: {}, coverage: {}, groups: {}, errors: {}}
        end

        def format_meta
          {
            simplecov_version: SimpleCov::VERSION,
            command_name: @result.command_name,
            project_name: SimpleCov.project_name,
            timestamp: @result.created_at.iso8601,
            root: SimpleCov.root,
            branch_coverage: SimpleCov.branch_coverage?,
            method_coverage: SimpleCov.method_coverage?
          }
        end

        def format_source_file(source_file)
          result = format_line_coverage(source_file)
          result.merge!(format_source_code(source_file))
          result.merge!(format_branch_coverage(source_file)) if SimpleCov.branch_coverage?
          result.merge!(format_method_coverage(source_file)) if SimpleCov.method_coverage?
          result
        end

        def format_source_code(source_file)
          {source: source_file.lines.map { |line| ensure_utf8(line.src.chomp) }}
        end

        def ensure_utf8(str)
          str.encode("UTF-8", invalid: :replace, undef: :replace)
        end

        def format_line_coverage(source_file)
          {
            lines: source_file.lines.map { |line| format_line(line) },
            lines_covered_percent: source_file.covered_percent,
            covered_lines: source_file.covered_lines.count,
            missed_lines: source_file.missed_lines.count
          }
        end

        def format_branch_coverage(source_file)
          {
            branches: source_file.branches.map { |branch| format_branch(branch) },
            branches_covered_percent: source_file.branches_coverage_percent,
            covered_branches: source_file.covered_branches.count,
            missed_branches: source_file.missed_branches.count,
            total_branches: source_file.total_branches.count
          }
        end

        def format_method_coverage(source_file)
          {
            methods: source_file.methods.map { |method| format_method(method) },
            methods_covered_percent: source_file.methods_coverage_percent,
            covered_methods: source_file.covered_methods.count,
            missed_methods: source_file.missed_methods.count,
            total_methods: source_file.methods.count
          }
        end

        def format_line(line)
          return line.coverage unless line.skipped?

          "ignored"
        end

        def format_branch(branch)
          {
            type: branch.type,
            start_line: branch.start_line,
            end_line: branch.end_line,
            coverage: format_line(branch),
            inline: branch.inline?,
            report_line: branch.report_line
          }
        end

        def format_method(method)
          {
            name: method.to_s,
            start_line: method.start_line,
            end_line: method.end_line,
            coverage: format_line(method)
          }
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
