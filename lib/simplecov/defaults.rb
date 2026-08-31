# frozen_string_literal: true

require "English"
require "pathname"
require_relative "formatter/html_formatter"

SimpleCov.configure do
  formatter SimpleCov::Formatter::HTMLFormatter

  load_profile "bundler_filter"
  load_profile "hidden_filter"
  load_profile "root_filter"
  load_profile "test_frameworks"
end

# Stashed as early as possible, before rake or test/unit tamper with ARGV
# (#110). The program name is kept separately as well: the join is lossy for
# a path containing a space, and the guesser reads the executable from it.
SimpleCov::CommandGuesser.original_run_command = "#{$PROGRAM_NAME} #{ARGV.join(' ')}"
SimpleCov::CommandGuesser.original_program_name = $PROGRAM_NAME

require_relative "load_global_config"

config_path = Pathname.new(SimpleCov.root)
loop do
  filename = config_path.join(".simplecov")
  if filename.exist?
    SimpleCov.with_dot_simplecov_autoload do
      load filename.to_s
    rescue LoadError, StandardError => e
      # simplecov:disable — only fires when .simplecov is unreadable
      # or raises during load
      warn "Warning: Error occurred while trying to load #{filename}. " \
           "Error message: #{e.message}"
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
