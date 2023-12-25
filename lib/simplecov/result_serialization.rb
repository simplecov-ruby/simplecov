# frozen_string_literal: true

module SimpleCov
  class ResultSerialization
    class << self
      def serialize(result)
        coverage = {}

        result.original_result.each do |file_path, file_data|
          serializable_file_data = {}

          file_data.each do |key, value|
            serializable_file_data[key] = serialize_value(key, value)
          end

          coverage[file_path] = serializable_file_data
        end

        data = {"coverage" => coverage, "timestamp" => result.created_at.to_i}
        {result.command_name => data}
      end

      def deserialize(hash) # rubocop:disable Metrics/MethodLength
        hash.map do |command_name, data|
          coverage = {}

          data.fetch("coverage").each do |file_name, file_data|
            parsed_file_data = {}

            file_data = {lines: file_data} if file_data.is_a?(Array)

            file_data.each do |key, value|
              key = key.to_sym
              parsed_file_data[key] = deserialize_value(key, value)
            end

            coverage[file_name] = parsed_file_data
          end

          result = SimpleCov::Result.new(coverage)
          result.command_name = command_name
          result.created_at = Time.at(data.fetch("timestamp"))
          result
        end
      end

    private

      def serialize_value(key, value) # rubocop:disable Metrics/MethodLength
        case key
        when :branches
          value.map { |k, v| [k, v.to_a] }
        when :methods
          value.map do |methods_data, coverage|
            klass, *info = methods_data
            # Replace all memory addresses with 0 since they are inconsistent between test runs
            serialized_klass = klass.to_s.sub(/0x[0-9a-f]{16}/, "0x0000000000000000")
            serialized_methods_data = [serialized_klass, *info]
            [serialized_methods_data, coverage]
          end
        else
          value
        end
      end

      def deserialize_value(key, value)
        case key
        when :branches
          deserialize_branches(value)
        when :methods
          deserialize_methods(value)
        else
          value
        end
      end

      def deserialize_branches(value)
        result = {}

        value.each do |serialized_root, serialized_coverage_data|
          root = deserialize_branch_info(serialized_root)
          coverage_data = {}

          serialized_coverage_data.each do |serialized_branch, coverage|
            branch = deserialize_branch_info(serialized_branch)
            coverage_data[branch] = coverage
          end

          result[root] = coverage_data
        end

        result
      end

      def deserialize_branch_info(value)
        value = adapt_old_style_branch_info(value) if value.is_a?(Symbol)
        type, *info = value
        [type.to_sym, *info]
      end

      def deserialize_methods(value)
        result = Hash.new { |hash, key| hash[key] = 0 }

        value.each do |serialized_info, coverage|
          klass, method_name, *info = serialized_info
          info = [klass, method_name.to_sym, *info]
          # Info keys might be non-unique since we replace memory addresses with 0
          result[info] += coverage
        end

        result
      end

      def adapt_old_style_branch_info(value)
        eval(value.to_s) # rubocop:disable Security/Eval
      end
    end
  end
end
