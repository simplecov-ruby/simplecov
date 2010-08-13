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
    
    should "have 4 covered_lines" do
      assert_equal 4, @source_file.covered_lines.count
    end
    
    should "have 5 never_lines" do
      assert_equal 5, @source_file.never_lines.count
    end
    
    should "have 1 missed_lines" do
      assert_equal 1, @source_file.missed_lines.count
    end
    
    should "have 90% covered_percent" do
      assert_equal 90.0, @source_file.covered_percent
    end
  end
end
