# frozen_string_literal: true

module SimpleCov
  # Group configuration is kept separate from inclusion and exclusion filters,
  # while sharing their matcher parser through the main Configuration module.
  module Configuration
    # Returns the configured groups. Add groups using SimpleCov.group.
    def groups
      @groups ||= {}
    end

    # The group set `SimpleCov.grouped` bins against when its caller
    # names none. It reads through a method of its own because the
    # keyword it defaults shadows this reader's name, so the default
    # has to name a receiver, and every spelling of that receiver is
    # the same call.
    #
    # mutant:disable — for that reason: `SimpleCov.groups`,
    # `self.groups` and `groups()` cannot be told apart.
    def default_groups
      groups
    end

    def groups=(new_groups)
      new_groups = new_groups.to_h { |name, filter| [GroupNames.normalize(name), filter] }
      GroupNames.validate!(new_groups.keys)
      @groups = new_groups
    end

    # Define a display group for files. Same matcher grammar as `skip`,
    # but instead of dropping the matching files it bins them under
    # `group_name` for the formatter. Files matched by no group fall
    # into the implicit "Ungrouped" bucket.
    def group(group_name, filter_argument = nil, &)
      group_name = GroupNames.normalize(group_name)
      GroupNames.validate!([group_name])
      groups[group_name] = parse_filter(filter_argument, &)
    end

    # DEPRECATED: alias for `group`. Same arguments, same behavior.
    def add_group(group_name, filter_argument = nil, &block)
      example = if block
                  "`SimpleCov.group #{group_name.inspect} { ... }`"
                else
                  "`SimpleCov.group #{group_name.inspect}, #{filter_argument.inspect}`"
                end
      Deprecation.warn(
        "`SimpleCov.add_group` is deprecated. " \
        "Replace with `SimpleCov.group` (same arguments, same behavior). Example: #{example}."
      )
      group(group_name, filter_argument, &block)
    end
  end
end
