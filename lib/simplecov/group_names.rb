# frozen_string_literal: true

module SimpleCov
  module GroupNames
    UNGROUPED = "Ungrouped"

    extend self

    # Group names are Hash keys, report labels, and JSON object keys all at once,
    # so they are normalized to Strings up front: a Symbol spelling means the
    # String, and anything else has no sensible serialized form. Normalizing
    # before `validate!` also keeps `group :Ungrouped` from slipping past the
    # reservation below.
    def normalize(group_name)
      case group_name
      when String then group_name
      when Symbol then group_name.to_s
      else
        raise ConfigurationError,
          "Group names must be Strings, got #{group_name.inspect} (#{group_name.class})"
      end
    end

    # Each name in turn, rather than asking the collection: a String asked
    # whether it "includes" the reserved name answers about its own characters.
    def validate!(group_names)
      return group_names unless group_names.any? { |name| name.eql?(UNGROUPED) }

      raise ConfigurationError,
        "#{UNGROUPED.inspect} is reserved for files that do not match a configured group"
    end
  end
end
