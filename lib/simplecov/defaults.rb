# Load default formatter gem
require 'simplecov-html'

# Default configuration
SimpleCov.configure do
  formatter SimpleCov::Formatter::HTMLFormatter
  # Exclude files outside of SimpleCov.root
  load_adapter 'root_filter'
end

at_exit do
  # Store the exit status of the test run since it goes away after calling the at_exit proc...
  @exit_status = $!.status if $!.is_a?(SystemExit)
  SimpleCov.at_exit.call
  exit @exit_status if @exit_status # Force exit with stored status (see github issue #5)
end

# Autoload config from .simplecov if present
config_path = File.join(SimpleCov.root, '.simplecov')
load config_path if File.exist?(config_path)