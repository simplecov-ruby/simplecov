# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "rspec integration", :sandbox do
  before { setup_project("faked_project") }

  let(:json) { coverage_json }
  let(:expected_file_percents) do
    {
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    }
  end
  let!(:result) do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
      #{SandboxProject::JSON_ALONGSIDE_HTML}
    RUBY
    run_command_and_expect_success(sorted_rspec_command)
  end

  it "generates a report from the basic two-line setup" do
    expect_coverage_report_generated(result)
  end

  it "totals the coverage" do
    expect(reported_total_percent(json)).to eq(88.09)
  end

  it "reports each file's percentage" do
    expect(reported_file_percents(json)).to eq(expected_file_percents)
  end
end
