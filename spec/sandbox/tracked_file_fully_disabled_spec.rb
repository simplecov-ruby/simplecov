# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "a tracked file with nothing left to cover", :sandbox do
  before { setup_project("faked_project") }

  let(:reported) { html_report_data.fetch("coverage").fetch("lib/all_disabled.rb") }
  let(:percents) do
    reported.values_at("lines_covered_percent", "branches_covered_percent", "methods_covered_percent")
  end

  let!(:result) do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        enable_coverage :branch
        enable_coverage :method
        track_files "lib/**/*.rb"
      end
    RUBY
    write_file("lib/all_disabled.rb", <<~RUBY)
      # simplecov:disable
      class AllDisabled
        def call(value)
          value ? :yes : :no
        end
      end
    RUBY
    run_command_and_expect_success(sorted_rspec_command)
  end

  it "generates a report" do
    expect_coverage_report_generated(result)
  end

  it "has nothing to cover under any criterion" do
    expect(reported.values_at("total_lines", "total_branches", "total_methods")).to eq([0, 0, 0])
  end

  it "reports it as fully covered, the way the source view renders it" do
    expect(percents).to eq([100.0, 100.0, 100.0])
  end
end
