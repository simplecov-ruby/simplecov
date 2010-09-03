#
# Code coverage for ruby 1.9. Please check out README for a full introduction.
#
module SimpleCov
  # Indicates invalid coverage data
  class CoverageDataError < StandardError; end;
  
  # The version of the simplecov gem
  VERSION = File.read(File.join(File.dirname(__FILE__), '../VERSION'))
  
  class << self
    attr_accessor :running#, :result # TODO: Remove result?
    
    #
    # Sets up SimpleCov to run against your project.
    # You can optionally specify an adapter to use as well as configuration with a block:
    #   SimpleCov.start
    #    OR
    #   SimpleCov.start 'rails' # using rails adapter
    #    OR
    #   SimpleCov.start do
    #     add_filter 'test'
    #   end
    #     OR
    #   SimpleCov.start 'rails' do
    #     add_filter 'test'
    #   end
    #
    # Please check out the RDoc for SimpleCov::Configuration to find about available config options
    #
    def start(adapter=nil, &block)
      unless "1.9".respond_to?(:encoding)
        warn "WARNING: SimpleCov is activated, but you're not running Ruby 1.9 - no coverage analysis will happen"
        return false
      end
      require 'coverage'
      load_adapter(adapter) unless adapter.nil?
      Coverage.start
      configure(&block) if block_given?
      @result = nil
      self.running = true
    end
    
    #
    # Returns the result for the current coverage run, merging it across test suites
    # from cache using SimpleCov::ResultMerger if use_merging is activated (default)
    #
    def result
      @result ||= SimpleCov::Result.new(Coverage.result) if running
      # If we're using merging of results, store the current result
      # first, then merge the results and return those
      if use_merging
        SimpleCov::ResultMerger.store_result(@result) if @result
        return SimpleCov::ResultMerger.merged_result
      else
        return @result
      end
    ensure
      self.running = false
    end
    
    #
    # Applies the configured filters to the given array of SimpleCov::SourceFile items
    #
    def filtered(files)
      result = files.clone
      filters.each do |filter|
        result = result.select {|source_file| filter.passes?(source_file) }
      end
      result
    end
    
    #
    # Applies the configured groups to the given array of SimpleCov::SourceFile items
    #
    def grouped(files)
      grouped = {}
      grouped_files = []
      groups.each do |name, filter|
        grouped[name] = files.select {|source_file| !filter.passes?(source_file)}
        grouped_files += grouped[name]
      end
      if groups.length > 0 and (other_files = files.reject {|source_file| grouped_files.include?(source_file)}).length > 0
        grouped["Ungrouped"] = other_files
      end
      grouped
    end
    
    # 
    # Applies the adapter of given name on SimpleCov configuration
    #
    def load_adapter(name)
      adapters.load(name)
    end
    
  end
end

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__)))
require 'simplecov/configuration'
SimpleCov.send :extend, SimpleCov::Configuration
require 'simplecov/adapters'
require 'simplecov/source_file'
require 'simplecov/result'
require 'simplecov/filter'
require 'simplecov/formatter'
require 'simplecov/merge_helpers'
require 'simplecov/result_merger'
require 'simplecov/command_guesser'
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