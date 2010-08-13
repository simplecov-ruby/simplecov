require 'helper'

class TestSourceFileLine < Test::Unit::TestCase
  context "A source line" do
    setup do
      @line = SimpleCov::SourceFile::Line.new('# the ruby source', 5, 3)
    end
    
    should 'return "# the ruby source" as src' do
      assert_equal '# the ruby source', @line.src
    end
    
    should 'return the same for source as for src' do
      assert_equal @line.src, @line.source
    end
    
    should 'have line number 5' do
      assert_equal 5, @line.line_number
    end
    
    should 'have equal line_number, line and number' do
      assert_equal @line.line_number, @line.line
      assert_equal @line.line_number, @line.number
    end
  end
  
  context "A source line with coverage" do
    setup do
      @line = SimpleCov::SourceFile::Line.new('# the ruby source', 5, 3)
    end
      
    should "have coverage of 3" do
      assert_equal 3, @line.coverage
    end
    
    should "be covered?" do
      assert @line.covered?
    end
    
    should "not be never?" do
      assert !@line.never?
    end
    
    should "not be missed?" do
      assert !@line.missed?
    end
  end
  
  context "A source line without coverage" do
    setup do
      @line = SimpleCov::SourceFile::Line.new('# the ruby source', 5, 0)
    end
      
    should "have coverage of 0" do
      assert_equal 0, @line.coverage
    end
    
    should "not be covered?" do
      assert !@line.covered?
    end
    
    should "not be never?" do
      assert !@line.never?
    end
    
    should "be missed?" do
      assert @line.missed?
    end
  end
  
  context "A source line with no code" do
    setup do
      @line = SimpleCov::SourceFile::Line.new('# the ruby source', 5, nil)
    end
      
    should "have nil coverage" do
      assert_nil @line.coverage
    end
    
    should "not be covered?" do
      assert !@line.covered?
    end
    
    should "be never?" do
      assert @line.never?
    end
    
    should "not be missed?" do
      assert !@line.missed?
    end
  end
  
  should "raise ArgumentError when initialized with invalid src" do
    assert_raise ArgumentError do
      SimpleCov::SourceFile::Line.new(:symbol, 5, 3)
    end
  end
  
  should "raise ArgumentError when initialized with invalid line_number" do
    assert_raise ArgumentError do
      SimpleCov::SourceFile::Line.new("some source", "five", 3)
    end
  end
  
  should "raise ArgumentError when initialized with invalid coverage" do
    assert_raise ArgumentError do
      SimpleCov::SourceFile::Line.new("some source", 5, "three")
    end
  end
end
