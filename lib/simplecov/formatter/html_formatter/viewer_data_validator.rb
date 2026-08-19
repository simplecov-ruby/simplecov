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
            data.fetch("groups").each { |name, group| validate_group!(name, group, meta) }
            validate_contexts!(data)
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

            source = file["source"]
            return if source.is_a?(Array) && source.all?(String)

            raise SimpleCov::CoverageJSON::Error,
                  "coverage entry #{filename.inspect} must include an array of source strings; " \
                  "regenerate with source_in_json true"
          end

          # Optional: a report without `track_tests` carries none. When
          # present, the viewer decodes both halves, so both are checked.
          def validate_contexts!(data)
            contexts = data["contexts"]
            unless contexts.nil? || (contexts.is_a?(Array) && contexts.all?(String))
              raise SimpleCov::CoverageJSON::Error, '"contexts" must be an array of strings'
            end

            count = contexts.is_a?(Array) ? contexts.size : 0
            data.fetch("coverage").each { |filename, file| validate_context_table!(filename, file["contexts"], count) }
          end

          # The viewer converts each key with Number() and indexes the
          # document's context list with it, and walks each value as hex
          # nibbles, so keys and values are held to exactly that contract.
          def validate_context_table!(filename, table, count)
            return if table.nil? || (table.is_a?(Hash) && table.all? { |key, value| context_entry?(key, value, count) })

            raise SimpleCov::CoverageJSON::Error,
                  "coverage entry #{filename.inspect} contexts must map recorded context indices to hex bitmaps"
          end

          def context_entry?(key, value, count)
            key.is_a?(String) && key.match?(/\A\d+\z/) && key.to_i < count &&
              value.is_a?(String) && value.match?(/\A\h+\z/)
          end

          def validate_meta!(meta)
            META_STRINGS.each { |key| validate_type!(meta, key, String, "meta") }
            validate_command_names!(meta)
            Time.iso8601(meta.fetch("timestamp"))
            COVERAGE_FLAGS.each_key { |key| validate_boolean!(meta, key) }
          rescue ArgumentError
            raise SimpleCov::CoverageJSON::Error, "meta.timestamp must be an ISO 8601 date-time"
          end

          # Optional: documents from before the key exists carry only the
          # joined command_name, which the viewer falls back to. When
          # present, the viewer counts and lists the entries, so it must
          # be an array of strings.
          def validate_command_names!(meta)
            names = meta["command_names"]
            return if names.nil? || (names.is_a?(Array) && names.all?(String))

            raise SimpleCov::CoverageJSON::Error, "meta.command_names must be an array of strings"
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
