module SimpleCov
  #
  # Representation of a source file including it's coverage data, source code,
  # source lines and featuring helpers to interpret that data.
  #
  class SourceFile
    # Representation of a single line in a source file including
    # this specific line's source code, line_number and code coverage,
    # with the coverage being either nil (coverage not applicable, e.g. comment
    # line), 0 (line not covered) or >1 (the amount of times the line was 
    # executed)
    class Line
      # The source code for this line. Aliased as :source
      attr_reader :src
      # The line number in the source file. Aliased as :line, :number
      attr_reader :line_number
      # The coverage data for this line: either nil (never), 0 (missed) or >=1 (times covered)
      attr_reader :coverage
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
    
      # Returns true if this is a line that should have been covered, but was not
      def missed?
        not never? and coverage == 0
      end
    
      # Returns true if this is a line that has been covered
      def covered?
        not never? and coverage > 0
      end
    
      # Returns true if this line is not relevant for coverage
      def never?
        coverage.nil?
      end
    end
  
    # The full path to this source file (e.g. /User/colszowka/projects/simplecov/lib/simplecov/source_file.rb)
    attr_reader :filename
    # The array of coverage data received from the Coverage.result
    attr_reader :coverage
    # The source code for this file. Aliased as :source
    attr_reader :src
    alias_method :source, :src
  
    def initialize(filename, coverage)
      @filename, @coverage, @src = filename, coverage, File.readlines(filename)
    end
    
    # Returns all source lines for this file as instances of SimpleCov::SourceFile::Line,
    # and thus including coverage data. Aliased as :source_lines
    def lines
      return @lines unless @lines.nil?
      # Initialize lines
      @lines = []
      coverage.each_with_index do |coverage, i|
        @lines << SimpleCov::SourceFile::Line.new(src[i], i+1, coverage)
      end
      @lines
    end
    alias_method :source_lines, :lines
    
    # Access SimpleCov::SourceFile::Line source lines by line number
    def line(number)
      lines[number-1]
    end
  
    # The coverage for this file in percent. 0 if the file has no relevant lines
    def covered_percent
      return 100.0 if lines.length == 0 or lines.length == never_lines.count
      (covered_lines.count) * 100 / (lines.count-never_lines.count).to_f
    end
  
    # Returns all covered lines as SimpleCov::SourceFile::Line
    def covered_lines
      @covered_lines ||= lines.select {|c| c.covered? }
    end
  
    # Returns all lines that should have been, but were not covered
    # as instances of SimpleCov::SourceFile::Line
    def missed_lines
      @missed_lines ||= lines.select {|c| c.missed? }
    end
  
    # Returns all lines that are not relevant for coverage as
    # SimpleCov::SourceFile::Line instances
    def never_lines
      @never_lines ||= lines.select {|c| c.never? }
    end
  end
end
