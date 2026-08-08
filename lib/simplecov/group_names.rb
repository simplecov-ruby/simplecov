# frozen_string_literal: true

module SimpleCov
  # Semantic names owned by result processing rather than user configuration.
  module GroupNames
    UNGROUPED = "Ungrouped"

  module_function

    # Group names are Hash keys, report labels, and JSON object keys all at
    # once, so they are normalized to Strings up front: a Symbol spelling
    # (`group :Controllers`) means the String, and anything else has no
    # sensible serialized form. Normalizing before `validate!` also keeps
    # `group :Ungrouped` from slipping past the reservation below.
    def normalize(group_name)
      case group_name
      when String then group_name
      when Symbol then group_name.to_s
      else
        raise SimpleCov::ConfigurationError,
              "Group names must be Strings, got #{group_name.inspect} (#{group_name.class})"
      end
    end

    def validate!(group_names)
      return group_names unless group_names.include?(UNGROUPED)

      raise SimpleCov::ConfigurationError,
            "#{UNGROUPED.inspect} is reserved for files that do not match a configured group"
    end
  end
end
