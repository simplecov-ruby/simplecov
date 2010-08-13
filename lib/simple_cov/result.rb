module SimpleCov
  class Result    
    attr_reader :original_result, :files

    def initialize(original_result)
      @original_result = original_result.freeze
      @files = original_result.map {|filename, coverage| SimpleCov::SourceFile.new(filename, coverage)}
      filter!
    end
  
    def filenames
      files.map(&:filename)
    end
  
    def filter!
      SimpleCov.filters.each do |filter|
        @files = files.reject {|source_file| filter.call(source_file) }
      end
    end
  end
end