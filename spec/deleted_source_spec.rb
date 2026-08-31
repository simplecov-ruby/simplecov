# frozen_string_literal: true

require "helper"

RSpec.describe "A source file which is subsequently deleted" do
  it "does not cause an error" do
    Dir.chdir(File.join(File.dirname(__FILE__), "fixtures")) do
      _stdout, _stderr, status = Open3.capture3("ruby", "deleted_source_sample.rb")
      expect(status.exitstatus).to be_zero
    end
  end
end
