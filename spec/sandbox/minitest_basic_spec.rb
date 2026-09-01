# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "minitest integration", :sandbox do
  before do
    setup_project("faked_project")
    self.bundle_with = "minitest"
    install_dependencies
  end

  let(:data) { html_report_data }

  describe "a rake-driven run" do
    let!(:result) do
      configure_simplecov(:minitest, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_filter "test_helper.rb"
        end
      RUBY
      run_command_and_expect_success("bundle exec rake minitest")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "totals the coverage" do
      expect(reported_total_percent(data)).to eq(87.50)
    end

    it "reports each file's percentage" do
      expect(reported_file_percents(data)).to eq(
        "lib/faked_project/some_class.rb" => 80.00,
        "minitest/some_test.rb" => 100.00
      )
    end
  end

  describe "a direct `ruby -I` run" do
    let!(:result) do
      configure_simplecov(:minitest, <<~RUBY)
        require 'simplecov'
        SimpleCov.start
      RUBY
      run_command_and_expect_success("bundle exec ruby -Ilib:minitest minitest/other_test.rb")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "totals the coverage" do
      expect(reported_total_percent(data)).to eq(80.00)
    end

    it "reports each file's percentage" do
      expect(reported_file_percents(data)).to eq("lib/faked_project/some_class.rb" => 80.00)
    end
  end

  describe "a run that never loads simplecov" do
    let!(:result) do
      configure_simplecov(:minitest, "# nothing\n")
      run_command_and_expect_success(
        "bundle exec rake minitest",
        env: {"SIMPLECOV_NO_REQUIRE_VERSION" => "0.22.0"}
      )
    end

    it "generates no report, and does not crash" do
      expect_no_coverage_report(result)
    end
  end
end
