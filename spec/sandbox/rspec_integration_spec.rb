# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Simply adding the basic simplecov lines to a project should get the
# user a coverage report after running `rspec`.
RSpec.describe "rspec integration", :sandbox do
  before { setup_project("faked_project") }

  it "generates a coverage report from the basic two-line setup" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
      #{SandboxProject::JSON_ALONGSIDE_HTML}
    RUBY

    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)

    json = coverage_json
    expect(reported_total_percent(json)).to eq(88.09)
    # spec/* files are filtered out by the default test_frameworks
    # profile, so only the four lib files appear.
    expect(reported_file_percents(json)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end
end
