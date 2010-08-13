module SimpleCov
  class SourceFile
    class Line
      attr_reader :src, :line_number, :coverage
      # Lets grab some fancy aliases, shall we?
      alias_method :source, :src
      alias_method :line, :line_number
      alias_method :number, :line_number
    
      def initialize(src, line_number, coverage)
        @src, @line_number, @coverage = src, line_number, coverage
      end
    
      def missed?
        coverage.kind_of?(Fixnum) and coverage == 0
      end
    
      def covered?
        coverage.kind_of?(Fixnum) and coverage > 0
      end
    
      def never?
        coverage.nil?
      end
    end
  
    attr_reader :filename, :coverage, :src, :lines
  
    def initialize(filename, coverage)
      @filename = filename
      @coverage = coverage.freeze
      @src = File.readlines(filename)
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
