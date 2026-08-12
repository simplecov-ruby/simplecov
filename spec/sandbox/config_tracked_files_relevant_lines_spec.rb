# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Files pulled in via `track_files` without ever being loaded still get
# their lines classified: comments and whitespace are irrelevant, :nocov:
# regions are skipped, and only genuinely executable lines count as
# relevant. The "2 relevant lines" summary the viewer renders from this
# data is covered by the bun suite (html_frontend/test/render_cells.test.ts).
RSpec.describe "tracked files line classification", :sandbox do
  before { setup_project("faked_project") }

  it "classifies comments, whitespace, and :nocov: regions in never-loaded files" do
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

    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)

    not_loaded = html_report_data.fetch("coverage").fetch("lib/not_loaded.rb")
    expect(not_loaded).to include("covered_lines" => 0, "total_lines" => 2)

    # Line-by-line classification: the :nocov: region (lines 3-6) is
    # "ignored", the comment/blank/`end` lines are irrelevant (null), and
    # the two relevant lines were never run.
    expect(not_loaded.fetch("lines")).to eq(
      [nil, nil, "ignored", "ignored", "ignored", "ignored", nil, 0, 0, nil]
    )
  end
end
