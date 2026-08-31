# frozen_string_literal: true

module SimpleCov
  # Configuration procs loaded with `SimpleCov.start :rails` and defined with
  # `SimpleCov.profiles.define`.
  class Profiles < Hash
    def define(name, &blk)
      name = name.to_sym
      raise ConfigurationError, "SimpleCov Profile '#{name}' is already defined" unless self[name].nil?

      self[name] = blk
    end

    def load(name)
      SimpleCov.configure(&fetch_proc(name))
    end

    # Lookup order: already registered via #define, then
    # `require "simplecov/profiles/<name>"` for the bundled profiles, then
    # `require "simplecov-profile-<name>"` for third-party plugin gems.
    def fetch_proc(name)
      name = name.to_sym
      autoload_profile(name) unless key?(name)
      return fetch(name) if key?(name)

      raise ConfigurationError, "Could not find SimpleCov Profile called '#{name}'"
    end

  private

    def autoload_profile(name)
      require "simplecov/profiles/#{name}"
    rescue LoadError
      begin
        require "simplecov-profile-#{name}"
      rescue LoadError
        # Neither a bundled profile nor a plugin gem; `fetch_proc` raises the
        # user-facing error.
      end
    end
  end
end
