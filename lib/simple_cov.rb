require 'coverage'
module SimpleCov
  class CoverageDataError < StandardError; end;
  
  class Filter
    attr_reader :filter_argument
    def initialize(filter_argument)
      @filter_argument = filter_argument
    end
    
    def passes?(source_file)
      raise "The base filter class is not intended for direct use"
    end
  end
  
  class StringFilter < SimpleCov::Filter
    def passes?(source_file)
      !(source_file.filename =~ /#{filter_argument}/)
    end
  end
  
  class BlockFilter < SimpleCov::Filter
    def passes?(source_file)
      !filter_argument.call(source_file)
    end
  end
  
  class << self
    attr_writer :filters
    def filters
      @filters ||= []
    end
    
    def add_filter(filter_argument=nil, &filter_proc)
      filters << filter
    end
  end
end

require 'simple_cov/source_file'
require 'simple_cov/result'