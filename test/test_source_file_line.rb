require "helper"

class TestSourceFileLine < Minitest::Test
  context "A source line" do
    setup do
      @line = SimpleCov::SourceFile::Line.new("# the ruby source", 5, 3)
    end
    subject { @line }

    should 'return "# the ruby source" as src' do
      assert_equal "# the ruby source", @line.src
    end

    should "return the same for source as for src" do
      assert_equal @line.src, @line.source
    end

    should "have line number 5" do
      assert_equal 5, @line.line_number
    end

    should "have equal line_number, line and number" do
      assert_equal @line.line_number, @line.line
      assert_equal @line.line_number, @line.number
    end

    context "flagged as skipped!" do
      setup { @line.skipped! }

      should_not_be :covered?
      should_be :skipped?
      should_not_be :missed?
      should_not_be :never?
      should_have :status, "skipped"
    end
  end

  context "A source line with coverage" do
    setup do
      @line = SimpleCov::SourceFile::Line.new("# the ruby source", 5, 3)
    end
    subject { @line }

    should "have coverage of 3" do
      assert_equal 3, @line.coverage
    end

    should_be :covered?
    should_not_be :skipped?
    should_not_be :missed?
    should_not_be :never?
    should_have :status, "covered"
  end

  context "A source line without coverage" do
    setup do
      @line = SimpleCov::SourceFile::Line.new("# the ruby source", 5, 0)
    end
    subject { @line }

    should "have coverage of 0" do
      assert_equal 0, @line.coverage
    end

    should_not_be :covered?
    should_not_be :skipped?
    should_be :missed?
    should_not_be :never?
    should_have :status, "missed"
  end

  context "A source line with no code" do
    setup do
      @line = SimpleCov::SourceFile::Line.new("# the ruby source", 5, nil)
    end
    subject { @line }

    should "have nil coverage" do
      assert_nil @line.coverage
    end

    should_not_be :covered?
    should_not_be :skipped?
    should_not_be :missed?
    should_be :never?
    should_have :status, "never"
  end

  should "raise ArgumentError when initialized with invalid src" do
    assert_raises ArgumentError do
      SimpleCov::SourceFile::Line.new(:symbol, 5, 3)
    end
  end

  should "raise ArgumentError when initialized with invalid line_number" do
    assert_raises ArgumentError do
      SimpleCov::SourceFile::Line.new("some source", "five", 3)
    end
  end

  should "raise ArgumentError when initialized with invalid coverage" do
    assert_raises ArgumentError do
      SimpleCov::SourceFile::Line.new("some source", 5, "three")
    end
  end
end if SimpleCov.usable?
