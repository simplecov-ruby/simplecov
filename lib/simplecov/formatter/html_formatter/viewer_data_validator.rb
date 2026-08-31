# frozen_string_literal: true

require "time"

module SimpleCov
  module Formatter
    class HTMLFormatter
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
            validate_production!(data)
            data
          end

        private

          def validate_section!(data, key)
            return if data[key].instance_of?(Hash)

            raise CoverageJSON::Error, "#{key.inspect} must be an object"
          end

          def validate_file!(filename, file)
            unless file.instance_of?(Hash)
              raise CoverageJSON::Error, "coverage entry #{filename.inspect} must be an object"
            end

            source = file["source"]
            return if source.instance_of?(Array) && source.all?(String)

            raise CoverageJSON::Error,
                  "coverage entry #{filename.inspect} must include an array of source strings; " \
                  "regenerate with source_in_json true"
          end

          def validate_contexts!(data)
            contexts = data["contexts"]
            unless contexts.nil? || (contexts.instance_of?(Array) && contexts.all?(String))
              raise CoverageJSON::Error, '"contexts" must be an array of strings'
            end

            count = Array(contexts).size
            data.fetch("coverage").each { |filename, file| validate_context_table!(filename, file["contexts"], count) }
          end

          def validate_context_table!(filename, table, count)
            return if table.nil? || (table.instance_of?(Hash) && table.all? do |key, value|
              context_entry?(key, value, count)
            end)

            raise CoverageJSON::Error,
                  "coverage entry #{filename.inspect} contexts must map recorded context indices to hex bitmaps"
          end

          def context_entry?(key, value, count)
            key.instance_of?(String) && key.match?(/\A\d+\z/) && Integer(key) < count &&
              value.instance_of?(String) && value.match?(/\A\h+\z/)
          end

          def validate_production!(data)
            production = data["production"]
            return if production.nil?

            raise CoverageJSON::Error, '"production" must be an object' unless production.instance_of?(Hash)

            files = validate_type!(production, "files", Hash, "production")
            files.each { |filename, entry| validate_production_file!(filename, entry) }
          end

          def validate_production_file!(filename, entry)
            unless production_lines?(entry)
              raise CoverageJSON::Error,
                    "production entry #{filename.inspect} must list sorted line numbers"
            end
            last_seen = entry["last_seen"]
            return if last_seen.nil? || last_seen.instance_of?(String)

            raise CoverageJSON::Error, "production entry #{filename.inspect} last_seen must be a string"
          end

          def production_lines?(entry)
            lines = entry["lines"] if entry.instance_of?(Hash)
            lines.instance_of?(Array) && lines.all? { |line| line.instance_of?(Integer) && line.positive? }
          end

          def validate_meta!(meta)
            META_STRINGS.each { |key| validate_type!(meta, key, String, "meta") }
            validate_command_names!(meta)
            Time.iso8601(meta.fetch("timestamp"))
            COVERAGE_FLAGS.each_key { |key| validate_boolean!(meta, key) }
          rescue ArgumentError
            raise CoverageJSON::Error, "meta.timestamp must be an ISO 8601 date-time"
          end

          def validate_command_names!(meta)
            names = meta["command_names"]
            return if names.nil? || (names.instance_of?(Array) && names.all?(String))

            raise CoverageJSON::Error, "meta.command_names must be an array of strings"
          end

          def validate_statistics!(statistics, meta, location)
            COVERAGE_FLAGS.each do |flag, criterion|
              next unless meta.fetch(flag)

              values = validate_type!(statistics, criterion, Hash, location)
              STAT_FIELDS.each { |field| validate_type!(values, field, Numeric, "#{location}.#{criterion}") }
            end
          end

          def validate_group!(name, group, meta)
            raise CoverageJSON::Error, "group #{name.inspect} must be an object" unless group.instance_of?(Hash)

            files = group["files"]
            unless files.instance_of?(Array) && files.all?(String)
              raise CoverageJSON::Error, "group #{name.inspect}.files must be an array of strings"
            end

            validate_statistics!(group, meta, "group #{name.inspect}")
          end

          def validate_type!(object, key, type, location)
            value = object[key]
            return value if value.is_a?(type)

            raise CoverageJSON::Error, "#{location}.#{key} must be a #{type.name.downcase}"
          end

          def validate_boolean!(meta, key)
            return if [true, false].include?(meta[key])

            raise CoverageJSON::Error, "meta.#{key} must be a boolean"
          end
        end
      end
    end
  end
end
