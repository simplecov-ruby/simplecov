# frozen_string_literal: true

module SimpleCov
  module Formatter
    class JSONFormatter
      # Translates the threshold violations reported by
      # `SimpleCov::CoverageViolations` into the `:errors` section of
      # coverage.json. Each violation is keyed by criterion
      # (`:lines` / `:branches` / `:methods`) so consumers can render
      # per-criterion messages without re-deriving them.
      class ErrorsFormatter
        CRITERION_KEYS = {line: :lines, branch: :branches, method: :methods}.freeze
        private_constant :CRITERION_KEYS

        def initialize(result)
          @result = result
          @errors = {}
        end

        def call
          format_minimum_overall
          format_minimum_by_file
          format_minimum_by_group
          format_maximum_overall
          format_maximum_drop
          @errors
        end

      private

        def format_minimum_overall
          SimpleCov::CoverageViolations.minimum_overall(@result, SimpleCov.minimum_coverage).each do |violation|
            bucket(:minimum_coverage)[key_for(violation)] = expected_actual(violation)
          end
        end

        def format_minimum_by_file
          violations = SimpleCov::CoverageViolations.minimum_by_file(
            @result, SimpleCov.minimum_coverage_by_file, SimpleCov.minimum_coverage_by_file_overrides
          )
          violations.each { |violation| record_by_file(violation) }
        end

        def record_by_file(violation)
          criterion_bucket = bucket(:minimum_coverage_by_file)[key_for(violation)] ||= {}
          criterion_bucket[violation.fetch(:project_filename)] = expected_actual(violation)
        end

        def format_minimum_by_group
          violations = SimpleCov::CoverageViolations.minimum_by_group(@result, SimpleCov.minimum_coverage_by_group)
          violations.each do |violation|
            group_bucket = bucket(:minimum_coverage_by_group)[violation.fetch(:group_name)] ||= {}
            group_bucket[key_for(violation)] = expected_actual(violation)
          end
        end

        def format_maximum_overall
          SimpleCov::CoverageViolations.maximum_overall(@result, SimpleCov.maximum_coverage).each do |violation|
            bucket(:maximum_coverage)[key_for(violation)] = expected_actual(violation)
          end
        end

        def format_maximum_drop
          SimpleCov::CoverageViolations.maximum_drop(@result, SimpleCov.maximum_coverage_drop).each do |violation|
            bucket(:maximum_coverage_drop)[key_for(violation)] =
              {maximum: violation.fetch(:maximum), actual: violation.fetch(:actual)}
          end
        end

        def bucket(name)
          @errors[name] ||= {}
        end

        def key_for(violation)
          CRITERION_KEYS.fetch(SimpleCov.coverage_statistics_key(violation.fetch(:criterion)))
        end

        def expected_actual(violation)
          {expected: violation.fetch(:expected), actual: violation.fetch(:actual)}
        end
      end
    end
  end
end
