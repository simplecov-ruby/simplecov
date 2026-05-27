# frozen_string_literal: true

module SimpleCov
  #
  # Profiles are SimpleCov configuration procs that can be easily
  # loaded using SimpleCov.start :rails and defined using
  #   SimpleCov.profiles.define :foo do
  #     # SimpleCov configuration here, same as in  SimpleCov.configure
  #   end
  #
  class Profiles < Hash
    #
    # Define a SimpleCov profile:
    #   SimpleCov.profiles.define 'rails' do
    #     # Same as SimpleCov.configure do .. here
    #   end
    #
    def define(name, &blk)
      name = name.to_sym
      raise SimpleCov::ConfigurationError, "SimpleCov Profile '#{name}' is already defined" unless self[name].nil?

      self[name] = blk
    end

    #
    # Applies the profile of given name on SimpleCov.configure
    #
    def load(name)
      SimpleCov.configure(&fetch_proc(name))
    end

    #
    # Returns the proc registered for the given profile name, autoloading
    # bundled or plugin-gem profiles on first lookup. Raises if the profile
    # cannot be located.
    #
    # Lookup order:
    #   1. already registered via #define
    #   2. require "simplecov/profiles/<name>"   (bundled profiles)
    #   3. require "simplecov-profile-<name>"    (third-party plugin gems)
    #
    def fetch_proc(name)
      name = name.to_sym
      autoload_profile(name) unless key?(name)
      return self[name] if key?(name)

      raise SimpleCov::ConfigurationError, "Could not find SimpleCov Profile called '#{name}'"
    end

  private

    def autoload_profile(name)
      require "simplecov/profiles/#{name}"
    rescue LoadError
      begin
        # simplecov:disable — third-party gem fallback (no such gem in test env)
        require "simplecov-profile-#{name}"
        # simplecov:enable
      rescue LoadError
        # fall through; #fetch_proc raises the user-facing error
      end
    end
  end
end
