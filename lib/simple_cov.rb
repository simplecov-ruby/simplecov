module SimpleCov
  class CoverageDataError < StandardError; end;
  
  class << self
    def filters
      @filters ||= []
    end
    
    def add_filter(&filter)
      filters << filter
    end
  end
end

require 'simple_cov/source_file'
require 'simple_cov/result'