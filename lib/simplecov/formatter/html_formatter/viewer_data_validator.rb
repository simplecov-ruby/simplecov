# frozen_string_literal: true

require "time"

module SimpleCov
  module Formatter
    class HTMLFormatter
      # Validates the subset of coverage.json that the browser viewer
      # dereferences without defensive fallbacks.
      module ViewerDataValidator
        META_STRINGS = %w[simplecov_version command_name project_name timestamp].freeze
        COVERAGE_FLAGS = {
          "line_coverage" => "lines",
          "branch_coverage" => "branches",
          "method_coverage" => "methods"
        }.freeze
        STAT_FIELDS = %w[covered missed total percent strength].freeze
        private_constant :META_STRINGS, :COVERAGE_FLAGS, :STAT_FIELDS

        class << self
          def call(data)
            %w[meta total coverage groups].each { |key| validate_section!(data, key) }
            meta = data.fetch("meta")
            validate_meta!(meta)
            validate_statistics!(data.fetch("total"), meta, "total")
            data.fetch("coverage").each { |filename, file| validate_file!(filename, file) }
            validate_contexts_coupling!(meta, data.fetch("coverage"))
            data.fetch("groups").each { |name, group| validate_group!(name, group, meta) }
            data
          end

        private

          def validate_section!(data, key)
            return if data[key].is_a?(Hash)

            raise SimpleCov::CoverageJSON::Error, "#{key.inspect} must be an object"
          end

          def validate_file!(filename, file)
            unless file.is_a?(Hash)
              raise SimpleCov::CoverageJSON::Error, "coverage entry #{filename.inspect} must be an object"
            end

            validate_file_test_contexts!(filename, file)
            source = file["source"]
            return if source.is_a?(Array) && source.all?(String)

            raise SimpleCov::CoverageJSON::Error,
                  "coverage entry #{filename.inspect} must include an array of source strings; " \
                  "regenerate with source_in_json true"
          end

          def validate_contexts_coupling!(meta, coverage)
            return unless meta["test_contexts"].nil?

            offender, = coverage.find { |_filename, file| !file["test_contexts"].nil? }
            return unless offender

            raise SimpleCov::CoverageJSON::Error,
                  "coverage entry #{offender.inspect} carries test_contexts but meta.test_contexts is missing"
          end

          def validate_file_test_contexts!(filename, file)
            contexts = file["test_contexts"]
            return if contexts.nil?
            return if contexts.is_a?(Hash) && contexts.each_value.all?(String)

            raise SimpleCov::CoverageJSON::Error,
                  "coverage entry #{filename.inspect}.test_contexts must map test indices to hex bitmap strings"
          end

          def validate_meta!(meta)
            META_STRINGS.each { |key| validate_type!(meta, key, String, "meta") }
            Time.iso8601(meta.fetch("timestamp"))
            COVERAGE_FLAGS.each_key { |key| validate_boolean!(meta, key) }
            validate_meta_test_contexts!(meta)
          rescue ArgumentError
            raise SimpleCov::CoverageJSON::Error, "meta.timestamp must be an ISO 8601 date-time"
          end

          def validate_meta_test_contexts!(meta)
            contexts = meta["test_contexts"]
            return if contexts.nil?

            tests = contexts.is_a?(Hash) ? contexts["tests"] : nil
            return if tests.is_a?(Array) && tests.all? { |test| test_entry?(test) }

            raise SimpleCov::CoverageJSON::Error, "meta.test_contexts.tests must be an array of id/name string pairs"
          end

          def test_entry?(test)
            test.is_a?(Hash) && test["id"].is_a?(String) && test["name"].is_a?(String)
          end

          def validate_statistics!(statistics, meta, location)
            COVERAGE_FLAGS.each do |flag, criterion|
              next unless meta.fetch(flag)

              values = validate_type!(statistics, criterion, Hash, location)
              STAT_FIELDS.each { |field| validate_type!(values, field, Numeric, "#{location}.#{criterion}") }
            end
          end

          def validate_group!(name, group, meta)
            raise SimpleCov::CoverageJSON::Error, "group #{name.inspect} must be an object" unless group.is_a?(Hash)

            files = group["files"]
            unless files.is_a?(Array) && files.all?(String)
              raise SimpleCov::CoverageJSON::Error, "group #{name.inspect}.files must be an array of strings"
            end

            validate_statistics!(group, meta, "group #{name.inspect}")
          end

          def validate_type!(object, key, type, location)
            value = object[key]
            return value if value.is_a?(type)

            raise SimpleCov::CoverageJSON::Error, "#{location}.#{key} must be a #{type.name.downcase}"
          end

          def validate_boolean!(meta, key)
            return if [true, false].include?(meta[key])

            raise SimpleCov::CoverageJSON::Error, "meta.#{key} must be a boolean"
          end
        end
      end
    end
  end
end
