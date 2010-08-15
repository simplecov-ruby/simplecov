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
    
    def groups
      @groups ||= SimpleCov.grouped(files)
    end
    
    def covered_percent
      files.map(&:covered_percent).inject(:+) / files.count.to_f
    end
    
    def format!
      SimpleCov.formatters.each do |formatter|
        formatter.format(self)
      end
    end
    
    private
  
    def filter!
      @files = SimpleCov.filtered(files)
    end
  end
end