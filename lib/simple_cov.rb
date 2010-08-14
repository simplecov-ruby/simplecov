require 'coverage'
module SimpleCov
  class CoverageDataError < StandardError; end;
  
  class << self
    attr_writer :filters
    def filters
      @filters ||= []
    end
    
    #
    # Add a filter to the processing chain.
    # There are three ways to define a filter:
    # 
    # * as a String that will then be matched against all source files' file paths,
    #   SimpleCov.add_filter 'app/models' # will reject all your models
    # * as a block which will be passed the source file in question and should either
    #   return a true or false value, depending on whether the file should be removed
    #   SimpleCov.add_filter do |src_file|
    #     File.basename(src_file.filename) == 'environment.rb'
    #   end # Will exclude environment.rb files from the results
    # * as an instance of a subclass of SimpleCov::Filter. See the documentation there
    #   on how to define your own filter classes
    #
    def add_filter(filter_argument=nil, &filter_proc)
      if filter_argument.kind_of?(SimpleCov::Filter)
        filters << filter_argument
      elsif filter_argument.kind_of?(String)
        filters << StringFilter.new(filter_argument)
      elsif filter_proc
        filters << BlockFilter.new(filter_proc)
      else
        raise ArgumentError, "Please specify either a string or a block to filter with"
      end
    end
    
    # Applies the configured filters on the given array of SimpleCov::SourceFile items
    def apply_filters(files)
      result = files.clone
      filters.each do |filter|
        result = result.select {|source_file| filter.passes?(source_file) }
      end
      result
    end
  end
end

require 'simple_cov/source_file'
require 'simple_cov/result'
require 'simple_cov/filter'