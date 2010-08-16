require 'helper'

class TestSourceFile < Test::Unit::TestCase
  context "A source file initialized with some coverage data" do
    setup do
      @source_file = SimpleCov::SourceFile.new(source_fixture('sample.rb'), [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
    end
    
    should "have a filename" do
      assert @source_file.filename
    end
    
    should "have source equal to src" do
      assert_equal @source_file.source, @source_file.src
    end
    
    should "have source_lines equal to lines" do
      assert_equal @source_file.source_lines, @source_file.lines
    end
    
    should "have 10 source lines" do
      assert_equal 10, @source_file.lines.count
    end
    
    should "have all source lines of type SimpleCov::SourceFile::Line" do
      assert @source_file.lines.all? {|l| l.instance_of?(SimpleCov::SourceFile::Line)}
    end
    
    should "have 'class Foo' as line(2).source" do
      assert_equal "class Foo\n", @source_file.line(2).source
    end
    
    should "return lines number 2, 3, 4, 7 for covered_lines" do
      assert_equal [2, 3, 4, 7], @source_file.covered_lines.map(&:line)
    end
    
    should "return lines number 8 for missed_lines" do
      assert_equal [8], @source_file.missed_lines.map(&:line)
    end
    
    should "return lines number 1, 5, 6, 9, 10 for never_lines" do
      assert_equal [1, 5, 6, 9, 10], @source_file.never_lines.map(&:line)
    end
    
    should "have 80% covered_percent" do
      assert_equal 80.0, @source_file.covered_percent
    end
  end
end
