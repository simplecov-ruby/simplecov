# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "complex groups and filters", :sandbox do
  before { setup_project("faked_project") }

  def expect_meta_magic_only(data)
    expect(reported_total_percent(data)).to eq(100.00)
    expect(reported_file_percents(data)).to eq("lib/faked_project/meta_magic.rb" => 100.00)
  end

  def expect_all_groups_hold_meta_magic(data)
    data.fetch("groups").each_value do |group|
      expect(displayed_percent(group.fetch("lines").fetch("percent"))).to eq(100.00)
      expect(group.fetch("files")).to eq(["lib/faked_project/meta_magic.rb"])
    end
  end

  context "with groups by block, string, and array (RSpec)" do
    before do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_group 'By block' do |src_file|
            src_file.filename =~ /MaGiC/i
          end
          add_group 'By string', 'faked_project/meta_magic'
          add_group 'By array', ['faked_project/meta_magic']

          add_filter 'faked_project.rb'
          # Remove all files that include "describe" in their source
          add_filter {|src_file| src_file.lines.any? {|line| line.src =~ /describe/ } }
          add_filter {|src_file| src_file.covered_percent < 100 }
        end
      RUBY
    end

    it "trims the report to one file present in every group" do
      result = run_command_and_expect_success(sorted_rspec_command)
      expect_coverage_report_generated(result)

      data = html_report_data
      expect_meta_magic_only(data)
      expect(data.fetch("groups").keys).to eq(["By block", "By string", "By array"])
      expect_all_groups_hold_meta_magic(data)
    end
  end

  context "with encoded and colliding group names (RSpec)" do
    before do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_group '<group' do |src_file|
            src_file.filename =~ /MaGiC/i
          end
          add_group '>group' do |src_file|
            src_file.filename =~ /framework_specific/i
          end
          add_group 'By/group' do |src_file|
            src_file.filename =~ /MaGiC/i
          end
          add_group 'By_2f_group' do |src_file|
            src_file.filename =~ /framework_specific/i
          end
          add_group 'All Files' do |src_file|
            src_file.filename =~ /framework_specific/i
          end

          add_filter 'faked_project.rb'
          add_filter {|src_file| src_file.lines.any? {|line| line.src =~ /describe/ } }
          add_filter {|src_file| src_file.covered_percent < 100 }
        end
      RUBY
    end

    it "keeps all five names distinct, including empty groups" do
      result = run_command_and_expect_success(sorted_rspec_command)
      expect_coverage_report_generated(result)

      data = html_report_data
      expect_meta_magic_only(data)

      expect(data.fetch("groups").keys).to eq(["<group", ">group", "By/group", "By_2f_group", "All Files"])
      expect(data.fetch("groups").transform_values { |group| group.fetch("files") }).to eq(
        "<group" => ["lib/faked_project/meta_magic.rb"],
        ">group" => [],
        "By/group" => ["lib/faked_project/meta_magic.rb"],
        "By_2f_group" => [],
        "All Files" => []
      )
    end
  end

  context "with groups by block and string (Test/Unit)" do
    before do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_group 'By block' do |src_file|
            src_file.filename =~ /MaGiC/i
          end
          add_group 'By string', 'faked_project/meta_magic'

          add_filter 'faked_project.rb'
          # Remove all files that include "TestCase" in their source
          add_filter {|src_file| src_file.lines.any? {|line| line.src =~ /TestCase/ } }
          add_filter {|src_file| src_file.covered_percent < 100 }
        end
      RUBY
    end

    it "trims the report to one file present in every group" do
      result = run_command_and_expect_success("bundle exec rake test")
      expect_coverage_report_generated(result)

      data = html_report_data
      expect_meta_magic_only(data)
      expect(data.fetch("groups").keys).to eq(["By block", "By string"])
      expect_all_groups_hold_meta_magic(data)
    end
  end
end
