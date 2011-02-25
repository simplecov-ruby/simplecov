require 'helper'

class TestDeletedSource < Test::Unit::TestCase
  on_ruby '1.8', '1.9' do
    context "A source file which is subsequently deleted" do
      should "not cause an error" do
        Dir.chdir(File.join(File.dirname(__FILE__), 'fixtures')) do
          `ruby deleted_source_sample.rb`
          assert_equal 0, $?.exitstatus
        end
      end
    end
  end
end
