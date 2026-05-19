# frozen_string_literal: true

require "helper"

RSpec.describe "coverage for eval" do # rubocop:disable RSpec/DescribeClass
  if SimpleCov.coverage_for_eval_supported?
    around do |test|
      Dir.chdir(File.join(File.dirname(__FILE__), "fixtures", "eval_test")) do
        FileUtils.rm_rf("./coverage")
        test.call
      end
    end

    let(:capture) { Open3.capture3("bundle e ruby eval_test.rb") }
    let(:stderr)  { capture[1] }
    let(:resultset) do
      capture # ensure the script ran first
      JSON.parse(File.read("./coverage/.resultset.json"))
    end

    it "produces a coverage report" do
      expect(stderr).to include("Coverage report generated")
    end

    it "records line hits for the eval'd .erb source" do
      coverage = resultset.values.first.fetch("coverage")
      erb_entry = coverage.find { |path, _data| path.end_with?("eval_test.erb") }
      expect(erb_entry).not_to be_nil

      lines = erb_entry.last.fetch("lines")
      # eval_test.erb runs the `if 1 + 1 == 2` branch — the "covered"
      # then-branch should be hit; the else stays at zero.
      expect(lines).to include(be_positive)
    end
  end
end
