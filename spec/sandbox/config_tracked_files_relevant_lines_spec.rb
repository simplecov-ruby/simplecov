# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "tracked files line classification", :sandbox do
  before { setup_project("faked_project") }

  let(:not_loaded) { html_report_data.fetch("coverage").fetch("lib/not_loaded.rb") }
  let!(:result) do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        track_files "lib/**/*.rb"
      end
    RUBY
    write_file("lib/not_loaded.rb", <<~RUBY)
      # A comment line. Plus a whitespace line below:

      # :nocov:
      def ignore_me
      end
      # :nocov:

      def this_is_relevant
        puts "still relevant"
      end
    RUBY
    run_command_and_expect_success(sorted_rspec_command)
  end

  it "generates a report" do
    expect_coverage_report_generated(result)
  end

  it "counts only the relevant lines of a never-loaded file" do
    expect(not_loaded).to include("covered_lines" => 0, "total_lines" => 2)
  end

  it "classifies comments, whitespace, and :nocov: regions" do
    expect(not_loaded.fetch("lines")).to eq(
      [nil, nil, "ignored", "ignored", "ignored", "ignored", nil, 0, 0, nil]
    )
  end
end
