# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Next to passing a block or a string to define a group, you can also
# pass a filter class. The filter class inherits from SimpleCov::Filter
# and must implement the matches? method, which is used to determine
# whether or not a file should be added to the group. Exercised for both
# RSpec and Test/Unit runs.
RSpec.describe "groups using a custom filter class", :sandbox do
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

  shared_examples "a filter-class grouped report" do
    before do
      configure_simplecov(framework, <<~RUBY)
        require 'simplecov'
        class CoverageFilter < SimpleCov::Filter
          def matches?(source_file)
            source_file.covered_percent < filter_argument
          end
        end
        SimpleCov.start do
          group 'By filter class', CoverageFilter.new(90)
          group 'By string', 'faked_project/meta_magic'
        end
      RUBY
    end

    it "buckets files by the filter class's covered-percent threshold" do
      result = run_command_and_expect_success(command)
      expect_coverage_report_generated(result)

      data = html_report_data
      expect(reported_total_percent(data)).to eq(88.09)
      expect_faked_project_file_percents(data)
      expect(data.fetch("groups").keys).to eq(["By filter class", "By string", "Ungrouped"])
      expect_group(data, "By filter class", percent: 78.26, files: %w[
                     lib/faked_project/some_class.rb
                     lib/faked_project/framework_specific.rb
                   ])
      expect_group(data, "By string", percent: 100.00, files: %w[lib/faked_project/meta_magic.rb])
      expect_group(data, "Ungrouped", percent: 100.00, files: %w[lib/faked_project.rb])
    end
  end

  context "with RSpec" do
    let(:framework) { :rspec }
    let(:command) { sorted_rspec_command }

    it_behaves_like "a filter-class grouped report"
  end

  context "with Test/Unit" do
    let(:framework) { :test_unit }
    let(:command) { "bundle exec rake test" }

    it_behaves_like "a filter-class grouped report"
  end
end
