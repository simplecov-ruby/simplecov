# frozen_string_literal: true

module SimpleCov
  class Baseline
    # Turns the YAML document of a baseline file into the
    # `{path => {criterion => Floor}}` entries `Baseline` holds. The canonical
    # shape is the criteria Hash `to_yaml` writes, but the lenient shapes stay
    # readable: a bare number is a line-percent floor, and a criterion may carry
    # a bare percent instead of the percent/missed pair. Anything else raises
    # ConfigurationError, naming the file and the offending entry: a malformed
    # policy must fail loudly rather than silently un-enforce every floor.
    module Parser
      extend self

      def call(data, path)
        raise ConfigurationError, "baseline file #{path} must map file paths to floors" unless data.is_a?(Hash)

        data.to_h { |file, entry| [file.to_s, parse_entry(file, entry, path)] }
      end

      def parse_entry(file, entry, path)
        return {line: Floor.new(percent: entry, missed: nil)} if entry.is_a?(Numeric)

        unless entry.is_a?(Hash)
          raise ConfigurationError, "baseline file #{path}: entry for #{file} must be a number or a criteria Hash"
        end

        entry.to_h do |criterion_key, floor|
          [parse_criterion(file, criterion_key, path), parse_floor(file, floor, path)]
        end
      end

      def parse_criterion(file, criterion_key, path)
        CRITERIA[criterion_key.to_s] || raise(
          ConfigurationError,
          "baseline file #{path}: unknown criterion #{criterion_key.inspect} for #{file} " \
          "(expected lines, branches, or methods)"
        )
      end

      def parse_floor(file, floor, path)
        return Floor.new(percent: floor, missed: nil) if floor.is_a?(Numeric)

        percent = floor["percent"] if floor.is_a?(Hash)
        unless percent.is_a?(Numeric)
          raise ConfigurationError, "baseline file #{path}: floor for #{file} needs a numeric percent"
        end

        missed = floor["missed"]
        unless missed.nil? || missed.instance_of?(Integer)
          raise ConfigurationError, "baseline file #{path}: missed count for #{file} must be an integer"
        end

        Floor.new(percent: percent, missed: missed)
      end
    end
  end
end
