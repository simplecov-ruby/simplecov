module SimpleCov
  #
  # Base filter class. Inherit from this to create custom filters,
  # and overwrite the passes?(source_file) instance method
  # 
  # # A sample class that rejects all source files.
  # class StupidFilter < SimpleCov::Filter
  #   def passes?(source_file)
  #     false
  #   end
  # end
  #
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
end