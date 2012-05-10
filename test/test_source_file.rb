require 'helper'

class TestSourceFile < Test::Unit::TestCase
  on_ruby '1.9' do
    COVERAGE_FOR_SAMPLE_RB = [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, nil, nil, nil, nil, nil]
    context "A source file initialized with some coverage data" do
      setup do
        @source_file = SimpleCov::SourceFile.new(source_fixture('sample.rb'), COVERAGE_FOR_SAMPLE_RB)
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

      should "have 16 source lines" do
        assert_equal 16, @source_file.lines.count
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

      should "return lines number 1, 5, 6, 9, 10, 11, 15, 16 for never_lines" do
        assert_equal [1, 5, 6, 9, 10, 11, 15, 16], @source_file.never_lines.map(&:line)
      end

      should "return line numbers 12, 13, 14 for skipped_lines" do
        assert_equal [12, 13, 14], @source_file.skipped_lines.map(&:line)
      end

      should "have 80% covered_percent" do
        assert_equal 80.0, @source_file.covered_percent
      end
    end

    context "Simulating potential Ruby 1.9 defect -- see Issue #56" do
      setup do
        @source_file = SimpleCov::SourceFile.new(source_fixture('sample.rb'), COVERAGE_FOR_SAMPLE_RB + [nil])
      end

      should "have 16 source lines regardless of extra data in coverage array" do
        # Do not litter test output with known warning
        capture_stderr { assert_equal 16, @source_file.lines.count }
      end

      should "print a warning to stderr if coverage array contains more data than lines in the file" do
        captured_output = capture_stderr do
          @source_file.lines
        end

        assert_match(/^Warning: coverage data provided/, captured_output)
      end
    end

    context "Encoding" do
      should "handle utf-8 encoded source files" do
        source_file = SimpleCov::SourceFile.new(source_fixture('utf-8.rb'), [nil, nil, 1])

        assert_nothing_raised do
          source_file.process_skipped_lines!
        end
      end

      should "handle iso-8859 encoded source files" do
        source_file = SimpleCov::SourceFile.new(source_fixture('iso-8859.rb'), [nil, nil, 1])

        assert_nothing_raised do
          source_file.process_skipped_lines!
        end
      end
    end

  end
end

