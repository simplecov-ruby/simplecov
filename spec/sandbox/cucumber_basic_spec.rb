# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Simply adding the basic simplecov lines to a project should get the
# user a coverage report after running `cucumber features` — the fixture
# project's own cucumber suite, run as a subprocess.
RSpec.describe "cucumber integration", :sandbox do
  before do
    setup_project("faked_project")
    # Cucumber runs here and nowhere else, so the fixture keeps it in an
    # optional Gemfile group that only this spec asks for.
    self.bundle_with = "cucumber"
    install_dependencies
  end

  it "generates a coverage report from the basic two-line setup" do
    configure_simplecov(:cucumber, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY

    result = run_command_and_expect_success("bundle exec cucumber features")
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for Cucumber Features")

    data = html_report_data
    expect(data.dig("meta", "command_name")).to eq("Cucumber Features")
    expect(reported_total_percent(data)).to eq(88.09)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end
end
