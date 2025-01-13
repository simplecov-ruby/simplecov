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

    before do
      @stdout, @stderr, @status = Open3.capture3(command)
    end

    context "foo" do
      let(:command) { "bundle e ruby eval_test.rb" }

      it "records coverage for erb" do
        expect(@stdout).to include("Line Coverage: 66.67% (2 / 3)")
      end
    end
  end
end
