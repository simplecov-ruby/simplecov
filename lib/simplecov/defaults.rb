# Load default formatter gem
require 'simplecov-html'

SimpleCov.adapters.define 'root_filter' do
  # Exclude all files outside of simplecov root
  add_filter do |src|
    !(src.filename =~ /^#{SimpleCov.root}/)
  end
end

SimpleCov.adapters.define 'test_frameworks' do
  add_filter '/test/'
  add_filter '/features/'
  add_filter '/spec/'
  add_filter '/autotest/'
end

SimpleCov.adapters.define 'rails' do
  load_adapter 'test_frameworks'

  add_filter '/config/'
  add_filter '/db/'
  add_filter '/vendor/bundle/'

  add_group 'Controllers', 'app/controllers'
  add_group 'Models', 'app/models'
  add_group 'Mailers', 'app/mailers'
  add_group 'Helpers', 'app/helpers'
  add_group 'Libraries', 'lib'
  add_group 'Plugins', 'vendor/plugins'
end

# Default configuration
SimpleCov.configure do
  formatter SimpleCov::Formatter::HTMLFormatter
  # Exclude files outside of SimpleCov.root
  load_adapter 'root_filter'
end

# Gotta stash this a-s-a-p, see the CommandGuesser class and i.e. #110 for further info
SimpleCov::CommandGuesser.original_run_command = "#{$0} #{ARGV.join(" ")}"

at_exit do
  # Store the exit status of the test run since it goes away after calling the at_exit proc...
  if $! #was an exception thrown?
    #if it was a SystemExit, use the accompanying status
    #otherwise set a non-zero status representing termination by some other exception
    #(see github issue 41)
    @exit_status = $!.is_a?(SystemExit) ? $!.status : 1
  end
  SimpleCov.at_exit.call
  exit @exit_status if @exit_status # Force exit with stored status (see github issue #5)
end

# Autoload config from .simplecov if present
config_path = File.join(SimpleCov.root, '.simplecov')
load config_path if File.exist?(config_path)
