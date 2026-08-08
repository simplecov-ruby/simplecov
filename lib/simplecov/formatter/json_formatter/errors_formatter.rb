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

        class << self
          def call(result)
            errors = {} #: Hash[Symbol, Hash[untyped, untyped]]
            format_minimum_overall(result, errors)
            format_minimum_by_file(result, errors)
            format_minimum_by_group(result, errors)
            format_maximum_overall(result, errors)
            format_maximum_drop(result, errors)
            errors
          end

        private

          def format_minimum_overall(result, errors)
            SimpleCov::CoverageViolations.minimum_overall(result, SimpleCov.minimum_coverage).each do |violation|
              bucket(errors, :minimum_coverage)[key_for(violation)] = expected_actual(violation)
            end
          end

          def format_minimum_by_file(result, errors)
            violations = SimpleCov::CoverageViolations.minimum_by_file(
              result, SimpleCov.minimum_coverage_by_file, SimpleCov.minimum_coverage_by_file_overrides
            )
            violations.each { |violation| record_by_file(violation, errors) }
          end

          def record_by_file(violation, errors)
            by_file = bucket(errors, :minimum_coverage_by_file)
            file_bucket = by_file[violation.fetch(:project_filename)] ||= {} #: Hash[untyped, untyped]
            file_bucket[key_for(violation)] = expected_actual(violation)
          end

          def format_minimum_by_group(result, errors)
            violations = SimpleCov::CoverageViolations.minimum_by_group(result, SimpleCov.minimum_coverage_by_group)
            return if violations.empty?

            # `bucket` lazily creates the errors key, so only touch it when
            # there is a violation to record.
            by_group = bucket(errors, :minimum_coverage_by_group)
            violations.each do |violation|
              group_bucket = by_group[violation.fetch(:group_name)] ||= {} #: Hash[untyped, untyped]
              group_bucket[key_for(violation)] = expected_actual(violation)
            end
          end

          def format_maximum_overall(result, errors)
            SimpleCov::CoverageViolations.maximum_overall(result, SimpleCov.maximum_coverage).each do |violation|
              bucket(errors, :maximum_coverage)[key_for(violation)] = expected_actual(violation)
            end
          end

          def format_maximum_drop(result, errors)
            SimpleCov::CoverageViolations.maximum_drop(result, SimpleCov.maximum_coverage_drop).each do |violation|
              bucket(errors, :maximum_coverage_drop)[key_for(violation)] =
                {maximum: violation.fetch(:maximum), actual: violation.fetch(:actual)}
            end
          end

          def bucket(errors, name)
            errors[name] ||= {} #: Hash[untyped, untyped]
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
end
