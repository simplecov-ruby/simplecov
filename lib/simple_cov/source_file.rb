module SimpleCov
  class SourceFile
    # Representation of a single line in a source file including
    # this specific line's source code, line_number and code coverage,
    # with the coverage being either nil (coverage not applicable, e.g. comment
    # line), 0 (line not covered) or >1 (the amount of times the line was 
    # executed)
    class Line
      attr_reader :src, :line_number, :coverage
      # Lets grab some fancy aliases, shall we?
      alias_method :source, :src
      alias_method :line, :line_number
      alias_method :number, :line_number
    
      def initialize(src, line_number, coverage)
        raise ArgumentError, "Only String accepted for source" unless src.kind_of?(String)
        raise ArgumentError, "Only Fixnum accepted for line_number" unless line_number.kind_of?(Fixnum)
        raise ArgumentError, "Only Fixnum and nil accepted for coverage" unless coverage.kind_of?(Fixnum) or coverage.nil?
        @src, @line_number, @coverage = src, line_number, coverage
      end
    
      def missed?
        not never? and coverage == 0
      end
    
      def covered?
        not never? and coverage > 0
      end
    
      def never?
        coverage.nil?
      end
    end
  
    attr_reader :filename, :coverage, :src, :lines
    alias_method :source, :src
    alias_method :source_lines, :lines
  
    def initialize(filename, coverage)
      @filename, @coverage, @src = filename, coverage, File.readlines(filename)
      @lines = []
      coverage.each_with_index do |coverage, i|
        @lines << SimpleCov::SourceFile::Line.new(src[i], i+1, coverage)
      end
    end
  
    def covered_percent
      return 100.0 if lines.length == 0
      (covered_lines.count + never_lines.count) * 100 / lines.count.to_f
    end
  
    def covered_lines
      @covered_lines ||= lines.select {|c| c.covered? }
    end
  
    def missed_lines
      @missed_lines ||= lines.select {|c| c.missed? }
    end
  
    def never_lines
      @never_lines ||= lines.select {|c| c.never? }
    end
  end
end
