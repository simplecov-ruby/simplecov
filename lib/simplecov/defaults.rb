# frozen_string_literal: true

require "pathname"
require_relative "formatter/html_formatter"

# Default configuration. Profiles autoload on first reference via
# `SimpleCov.profiles.fetch_proc`; the unused ones (e.g. "rails",
# "test_frameworks") never get required unless a user opts in.
SimpleCov.configure do
  formatter SimpleCov::Formatter::HTMLFormatter

  load_profile "bundler_filter"
  load_profile "hidden_filter"
  # Exclude files outside of SimpleCov.root. Mirrors the early prune done
  # by SimpleCov::UselessResultsRemover so the user-facing filter chain
  # honors the same boundary; both share the regex.
  load_profile "root_filter"
end

# Gotta stash this a-s-a-p, see the CommandGuesser class and i.e. #110 for further info
SimpleCov::CommandGuesser.original_run_command = "#{$PROGRAM_NAME} #{ARGV.join(' ')}"

# Autoload config from ~/.simplecov if present
require_relative "load_global_config"

# Autoload config from .simplecov if present
# Recurse upwards until we find .simplecov or reach the root directory

config_path = Pathname.new(SimpleCov.root)
loop do
  filename = config_path.join(".simplecov")
  if filename.exist?
    begin
      load filename
    rescue LoadError, StandardError
      # simplecov:disable — only fires when .simplecov is unreadable
      # or raises during load
      warn "Warning: Error occurred while trying to load #{filename}. " \
           "Error message: #{$!.message}"
      # simplecov:enable
    end
    break
  end
  # simplecov:disable — only fires when no .simplecov is found up to
  # the filesystem root; simplecov's own dogfood run finds the repo's
  # .simplecov on the first iteration and breaks before getting here.
  config_path, = config_path.split
  break if config_path.root?
  # simplecov:enable
end
