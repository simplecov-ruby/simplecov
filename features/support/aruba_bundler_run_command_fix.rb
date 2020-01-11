# frozen_string_literal: true

# Our current Aruba version can't work under a new bundler environment
# which we'd actually kinda like to have :)
# See: https://github.com/cucumber/aruba/issues/699
# This is then taken/adjusted from: https://github.com/rspec/rspec-rails/blob/64b2712da9d12c03a582bb26b62337504f8d1b76/features/support/env.rb

raise "Check if we still need this freedom patch" if Aruba::VERSION[0] == "1"

module ArubaExt
  def run_command(*_)
    unset_bundler_env_vars
    in_current_directory do
      Bundler.with_unbundled_env do
        super
      end
    end
  end

  def unset_bundler_env_vars
    empty_env = with_environment { Bundler.with_unbundled_env { ENV.to_h } }
    aruba_env = aruba.environment.to_h
    (aruba_env.keys - empty_env.keys).each do |key|
      delete_environment_variable key
    end
    empty_env.each do |k, v|
      set_environment_variable k, v
    end
  end
end

World(ArubaExt)
