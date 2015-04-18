require "helper"

class TestFilters < Minitest::Test
  context "A source file initialized with some coverage data" do
    setup do
      @source_file = SimpleCov::SourceFile.new(source_fixture("sample.rb"), [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
    end

    should "not match a new SimpleCov::StringFilter 'foobar'" do
      assert !SimpleCov::StringFilter.new("foobar").matches?(@source_file)
    end

    should "not match a new SimpleCov::StringFilter 'some/path'" do
      assert !SimpleCov::StringFilter.new("some/path").matches?(@source_file)
    end

    should "match a new SimpleCov::StringFilter 'test/fixtures'" do
      assert SimpleCov::StringFilter.new("test/fixtures").matches?(@source_file)
    end

    should "match a new SimpleCov::StringFilter 'test/fixtures/sample.rb'" do
      assert SimpleCov::StringFilter.new("test/fixtures/sample.rb").matches?(@source_file)
    end

    should "match a new SimpleCov::StringFilter 'sample.rb'" do
      assert SimpleCov::StringFilter.new("sample.rb").matches?(@source_file)
    end

    should "not match a new SimpleCov::BlockFilter that is not applicable" do
      assert !SimpleCov::BlockFilter.new(proc { |s| File.basename(s.filename) == "foo.rb" }).matches?(@source_file)
    end

    should "match a new SimpleCov::BlockFilter that is applicable" do
      assert SimpleCov::BlockFilter.new(proc { |s| File.basename(s.filename) == "sample.rb" }).matches?(@source_file)
    end

    should "match a new SimpleCov::ArrayFilter when 'sample.rb' is passed as array" do
      assert SimpleCov::ArrayFilter.new(["sample.rb"]).matches?(@source_file)
    end

    should "not match a new SimpleCov::ArrayFilter when a file path different than 'sample.rb' is passed as array" do
      assert !SimpleCov::ArrayFilter.new(["other_file.rb"]).matches?(@source_file)
    end

    should "match a new SimpleCov::ArrayFilter when two file paths including 'sample.rb' are passed as array" do
      assert SimpleCov::ArrayFilter.new(["sample.rb", "other_file.rb"]).matches?(@source_file)
    end
  end

  context "with no filters set up and a basic source file in an array" do
    setup do
      @prev_filters, SimpleCov.filters = SimpleCov.filters, []
      @files = [SimpleCov::SourceFile.new(source_fixture("sample.rb"), [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])]
    end

    teardown do
      SimpleCov.filters = @prev_filters
    end

    should "return 0 items after executing SimpleCov.filtered on files when using a 'sample' string filter" do
      SimpleCov.add_filter "sample"
      assert_equal 0, SimpleCov.filtered(@files).count
    end

    should "return 0 items after executing SimpleCov.filtered on files when using a 'test/fixtures/' string filter" do
      SimpleCov.add_filter "test/fixtures"
      assert_equal 0, SimpleCov.filtered(@files).count
    end

    should "return 1 item after executing SimpleCov.filtered on files when using a 'fooo' string filter" do
      SimpleCov.add_filter "fooo"
      assert_equal 1, SimpleCov.filtered(@files).count
    end

    should "return 0 items after executing SimpleCov.filtered on files when using a block filter that returns true" do
      SimpleCov.add_filter do
        true
      end
      assert_equal 0, SimpleCov.filtered(@files).count
    end

    should "return 1 item after executing SimpleCov.filtered on files when using an always-false block filter" do
      SimpleCov.add_filter do
        false
      end
      assert_equal 1, SimpleCov.filtered(@files).count
    end

    should "return a FileList after filtering" do
      SimpleCov.add_filter "fooo"
      assert_equal SimpleCov::FileList, SimpleCov.filtered(@files).class
    end
  end
end if SimpleCov.usable?
