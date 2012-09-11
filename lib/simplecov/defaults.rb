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
    @exit_status = $!.is_a?(SystemExit) ? $!.status : SimpleCov::ExitCodes::EXCEPTION
  end

  SimpleCov.at_exit.call

  if SimpleCov.result? # Result has been computed
    covered_percent = SimpleCov.result.covered_percent.round(2)

    if @exit_status.to_i == 0 # No other errors
      @exit_status = if covered_percent < SimpleCov.minimum_coverage
        $stderr.puts "Coverage (%.2f%%) is below the expected minimum coverage (%.2f%%)." % \
                     [covered_percent, SimpleCov.minimum_coverage]

        SimpleCov::ExitCodes::MINIMUM_COVERAGE

      elsif (last_run = SimpleCov::LastRun.read)
        diff = last_run['result']['covered_percent'] - covered_percent
        if diff > SimpleCov.maximum_coverage_drop
          $stderr.puts "Coverage has dropped by %.2f%% since the last time (maximum allowed: %.2f%%)." % \
                       [diff, SimpleCov.maximum_coverage_drop]

          SimpleCov::ExitCodes::MAXIMUM_COVERAGE_DROP
        end
      end
    end

    metrics = {
      :result => { :covered_percent => covered_percent }
    }
    SimpleCov::LastRun.write(metrics)
  end

  exit @exit_status if @exit_status # Force exit with stored status (see github issue #5)
end

# Autoload config from .simplecov if present
config_path = File.join(SimpleCov.root, '.simplecov')
load config_path if File.exist?(config_path)
