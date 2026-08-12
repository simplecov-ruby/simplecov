# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Defining some groups and filters should give a corresponding coverage
# report that respects those settings, for both RSpec and Test/Unit runs.
# The report data (embedded in index.html for the viewer) carries the
# groups in configuration order with their stats and file lists; the
# interactive side the cucumber suite clicked through (tab switching,
# column sorting and the sort indicators) is covered by the bun suite in
# html_frontend/test/{app,sort}.test.ts.
RSpec.describe "groups and filters", :sandbox do
  before { setup_project("faked_project") }

  # Asserts one group's displayed percent and exact membership.
  def expect_group(data, name, percent:, files:)
    group = reported_group(data, name)
    expect(displayed_percent(group.fetch("lines").fetch("percent"))).to eq(percent)
    expect(group.fetch("files")).to match_array(files)
  end

  def expect_faked_project_file_percents(data)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end

  shared_examples "a grouped report" do
    it "groups the lib files and filters the test suite out" do
      result = run_command_and_expect_success(command)
      expect_coverage_report_generated(result)

      data = html_report_data
      expect(reported_total_percent(data)).to eq(88.09)
      expect_faked_project_file_percents(data)
      expect(data.fetch("groups").keys).to eq(%w[Libs Ungrouped])
      expect_group(data, "Libs", percent: 86.11, files: %w[
                     lib/faked_project/some_class.rb
                     lib/faked_project/framework_specific.rb
                     lib/faked_project/meta_magic.rb
                   ])
      expect_group(data, "Ungrouped", percent: 100.00, files: %w[lib/faked_project.rb])
    end
  end

  context "with RSpec" do
    before do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_group 'Libs', 'lib/faked_project/'
          add_filter '/spec/'
        end
      RUBY
    end

    let(:command) { sorted_rspec_command }

    it_behaves_like "a grouped report"
  end

  context "with Test/Unit" do
    before do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_group 'Libs', 'lib/faked_project/'
          add_filter '/test/'
        end
      RUBY
    end

    let(:command) { "bundle exec rake test" }

    it_behaves_like "a grouped report"
  end
end
