# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "tracked files", :sandbox do
  before { setup_project("faked_project") }

  it "reports files matched by track_files even when they were never loaded" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        track_files "lib/**/*.rb"
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)

    data = html_report_data
    expect(reported_total_percent(data)).to eq(77.08)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/untested_class.rb" => 0.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end
end
