module SimpleCov
  class Result    
    attr_reader :original_result, :files
    alias_method :source_files, :files

    def initialize(original_result)
      @original_result = original_result.freeze
      @files = original_result.map {|filename, coverage| SimpleCov::SourceFile.new(filename, coverage)}
      filter!
    end
  
    def filenames
      files.map(&:filename)
    end
    
    def covered_percent
      files.map(&:covered_percent).inject(:+) / files.count.to_f
    end
  
    def filter!
      @files = SimpleCov.apply_filters(files)
    end
  end
end