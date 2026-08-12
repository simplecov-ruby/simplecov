# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Working with minitest: rake-driven and direct `ruby -I` runs both
# produce reports, and an empty config with simplecov merely installed
# does not crash the run (see issue #877).
RSpec.describe "minitest integration", :sandbox do
  before do
    setup_project("faked_project")
    # Minitest runs here and nowhere else, so the fixture keeps it in an
    # optional Gemfile group that only this spec asks for.
    self.bundle_with = "minitest"
    install_dependencies
  end

  it "generates a coverage report from a rake-driven run" do
    configure_simplecov(:minitest, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter "test_helper.rb"
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake minitest")
    expect_coverage_report_generated(result)

    data = html_report_data
    expect(reported_total_percent(data)).to eq(87.50)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project/some_class.rb" => 80.00,
      "minitest/some_test.rb" => 100.00
    )
  end

  it "generates a coverage report from a direct `ruby -I` run" do
    configure_simplecov(:minitest, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY

    result = run_command_and_expect_success("bundle exec ruby -Ilib:minitest minitest/other_test.rb")
    expect_coverage_report_generated(result)

    data = html_report_data
    expect(reported_total_percent(data)).to eq(80.00)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project/some_class.rb" => 80.00
    )
  end

  it "does not crash when simplecov is never loaded (#877)" do
    configure_simplecov(:minitest, <<~RUBY)
      # nothing
    RUBY

    # Path requirements in the Gemfile evaluate the gemspec, which normally
    # loads the version, which defines SimpleCov, which leads to a different
    # failure. The variable works around that (carried over from the
    # cucumber scenario).
    result = run_command_and_expect_success(
      "bundle exec rake minitest",
      env: {"SIMPLECOV_NO_REQUIRE_VERSION" => "0.22.0"}
    )
    expect_no_coverage_report(result)
  end
end
