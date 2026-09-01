# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "groups using a custom filter class", :sandbox do
  before { setup_project("faked_project") }

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
          add_group 'By filter class', CoverageFilter.new(90)
          add_group 'By string', 'faked_project/meta_magic'
        end
      RUBY
    end

    let!(:result) { run_command_and_expect_success(command) }
    let(:data) { html_report_data }
    let(:under_threshold) do
      %w[
        lib/faked_project/some_class.rb
        lib/faked_project/framework_specific.rb
      ]
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "totals the coverage" do
      expect(reported_total_percent(data)).to eq(88.09)
    end

    it "reports each file's percentage" do
      expect_faked_project_file_percents(data)
    end

    it "names the groups" do
      expect(data.fetch("groups").keys).to eq(["By filter class", "By string", "Ungrouped"])
    end

    it "buckets the files under the filter class's threshold" do
      expect_group(data, "By filter class", percent: 78.26, files: under_threshold)
    end

    it "buckets the file matched by string" do
      expect_group(data, "By string", percent: 100.00, files: %w[lib/faked_project/meta_magic.rb])
    end

    it "leaves the rest ungrouped" do
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
