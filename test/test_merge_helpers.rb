require "helper"

class TestMergeHelpers < Minitest::Test
  def self.test_order
    :alpha
  end

  context "With two faked coverage resultsets" do
    setup do
      SimpleCov.use_merging true
      @resultset1 = {
        source_fixture("sample.rb") => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
        source_fixture("app/models/user.rb") => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
        source_fixture("app/controllers/sample_controller.rb") => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
        source_fixture("resultset1.rb") => [1, 1, 1, 1],
      }

      @resultset2 = {
        source_fixture("sample.rb") => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil],
        source_fixture("app/models/user.rb") => [nil, 1, 5, 1, nil, nil, 1, 0, nil, nil],
        source_fixture("app/controllers/sample_controller.rb") => [nil, 3, 1, nil, nil, nil, 1, 0, nil, nil],
        source_fixture("resultset2.rb") => [nil, 1, 1, nil],
      }
    end

    context "a merge" do
      setup do
        assert @merged = @resultset1.merge_resultset(@resultset2)
      end

      should "have proper results for sample.rb" do
        assert_equal [1, 1, 2, 2, nil, nil, 2, 2, nil, nil], @merged[source_fixture("sample.rb")]
      end

      should "have proper results for user.rb" do
        assert_equal [nil, 2, 6, 2, nil, nil, 2, 0, nil, nil], @merged[source_fixture("app/models/user.rb")]
      end

      should "have proper results for sample_controller.rb" do
        assert_equal [nil, 4, 2, 1, nil, nil, 2, 0, nil, nil], @merged[source_fixture("app/controllers/sample_controller.rb")]
      end

      should "have proper results for resultset1.rb" do
        assert_equal [1, 1, 1, 1], @merged[source_fixture("resultset1.rb")]
      end

      should "have proper results for resultset2.rb" do
        assert_equal [nil, 1, 1, nil], @merged[source_fixture("resultset2.rb")]
      end
    end

    # See Github issue #6
    should "return an empty hash when the resultset cache file is empty" do
      File.open(SimpleCov::ResultMerger.resultset_path, "w+") { |f| f.puts "" }
      assert_empty SimpleCov::ResultMerger.resultset
    end

    # See Github issue #6
    should "return an empty hash when the resultset cache file is not present" do
      system "rm #{SimpleCov::ResultMerger.resultset_path}" if File.exist?(SimpleCov::ResultMerger.resultset_path)
      assert_empty SimpleCov::ResultMerger.resultset
    end

    context "and results generated from those" do
      setup do
        system "rm #{SimpleCov::ResultMerger.resultset_path}" if File.exist?(SimpleCov::ResultMerger.resultset_path)
        @result1 = SimpleCov::Result.new(@resultset1)
        @result1.command_name = "result1"
        @result2 = SimpleCov::Result.new(@resultset2)
        @result2.command_name = "result2"
      end

      context "with stored results" do
        setup do
          assert SimpleCov::ResultMerger.store_result(@result1)
          assert SimpleCov::ResultMerger.store_result(@result2)
        end

        should "have stored data in resultset_path JSON file" do
          assert File.readlines(SimpleCov::ResultMerger.resultset_path).length > 50
        end

        should "return a hash containing keys ['result1' and 'result2'] for resultset" do
          assert_equal %w(result1 result2), SimpleCov::ResultMerger.resultset.keys.sort
        end

        should "return proper values for merged_result" do
          assert_equal [nil, 2, 6, 2, nil, nil, 2, 0, nil, nil], SimpleCov::ResultMerger.merged_result.source_files.find { |s| s.filename =~ /user/ }.lines.map(&:coverage)
        end

        context "with second result way above the merge_timeout" do
          setup do
            @result2.created_at = Time.now - 172_800 # two days ago
            assert SimpleCov::ResultMerger.store_result(@result2)
          end

          should "have only one result in SimpleCov::ResultMerger.results" do
            assert_equal 1, SimpleCov::ResultMerger.results.length
          end
        end

        context "with merging disabled" do
          setup { SimpleCov.use_merging false }

          should "return nil for SimpleCov.result" do
            assert_nil SimpleCov.result
          end
        end
      end
    end
  end
end if SimpleCov.usable?
