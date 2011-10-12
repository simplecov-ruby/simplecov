require 'helper'

class TestFilters < Test::Unit::TestCase
  on_ruby '1.9' do
    context "A source file initialized with some coverage data" do
      setup do
        @source_file = SimpleCov::SourceFile.new(source_fixture('sample.rb'), [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
      end

      should "not match a new SimpleCov::StringFilter 'foobar'" do
        assert !SimpleCov::StringFilter.new('foobar').matches?(@source_file)
      end

      should "not match a new SimpleCov::StringFilter 'some/path'" do
        assert !SimpleCov::StringFilter.new('some/path').matches?(@source_file)
      end

      should "match a new SimpleCov::StringFilter 'test/fixtures'" do
        assert SimpleCov::StringFilter.new('test/fixtures').matches?(@source_file)
      end

      should "match a new SimpleCov::StringFilter 'test/fixtures/sample.rb'" do
        assert SimpleCov::StringFilter.new('test/fixtures/sample.rb').matches?(@source_file)
      end

      should "match a new SimpleCov::StringFilter 'sample.rb'" do
        assert SimpleCov::StringFilter.new('sample.rb').matches?(@source_file)
      end

      should "not match a new SimpleCov::BlockFilter that is not applicable" do
        assert !SimpleCov::BlockFilter.new(Proc.new {|s| File.basename(s.filename) == 'foo.rb'}).matches?(@source_file)
      end

      should "match a new SimpleCov::BlockFilter that is applicable" do
        assert SimpleCov::BlockFilter.new(Proc.new {|s| File.basename(s.filename) == 'sample.rb'}).matches?(@source_file)
      end
    end

    context "with no filters set up and a basic source file in an array" do
      setup do
        SimpleCov.filters = []
        @files = [SimpleCov::SourceFile.new(source_fixture('sample.rb'), [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])]
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
        SimpleCov.add_filter do |src_file|
          true
        end
        assert_equal 0, SimpleCov.filtered(@files).count
      end

      should "return 1 item after executing SimpleCov.filtered on files when using an always-false block filter" do
        SimpleCov.add_filter do |src_file|
          false
        end
        assert_equal 1, SimpleCov.filtered(@files).count
      end

      should "return a FileList after filtering" do
        SimpleCov.add_filter "fooo"
        assert_equal SimpleCov::FileList, SimpleCov.filtered(@files).class
      end
    end
  end
end
