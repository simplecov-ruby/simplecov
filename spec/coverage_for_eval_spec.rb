# frozen_string_literal: true

require "helper"

RSpec.describe "coverage for eval" do
  if SimpleCov.coverage_for_eval_supported?
    around do |test|
      Dir.chdir(File.join(File.dirname(__FILE__), "fixtures", "eval_test")) do
        FileUtils.rm_rf("./coverage")
        test.call
      end
    end

    let(:capture) { Open3.capture3("bundle e ruby eval_test.rb") }
    let(:stderr) { capture[1] }
    let(:resultset) do
      capture
      JSON.parse(File.read("./coverage/.resultset.json"))
    end
    let(:erb_entry) do
      resultset.values.first.fetch("coverage").find { |path, _data| path.end_with?("eval_test.erb") }
    end

    it "produces a coverage report" do
      expect(stderr).to include("Coverage report generated")
    end

    it "records the eval'd .erb source" do
      expect(erb_entry).not_to be_nil
    end

    it "records line hits for it" do
      expect(erb_entry.last.fetch("lines")).to include(be_positive)
    end
  end
end
