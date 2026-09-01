# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "no_defaults configuration", :sandbox do
  before { setup_project("faked_project") }

  describe "loading no default formatter" do
    let!(:result) do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov/no_defaults'

        SimpleCov.start do
          command_name "No Defaults"
        end
      RUBY
      run_command_and_expect_success("bundle exec rake test")
    end

    it "writes a resultset" do
      expect(file_exist?("coverage/.resultset.json")).to be(true)
    end

    it "renders no report" do
      expect(file_exist?("coverage/index.html")).to be(false)
    end

    it "announces no report" do
      expect(result.output).not_to include("Coverage report generated")
    end
  end

  describe "loading no default filters" do
    let(:files) { html_report_data.fetch("coverage").keys }
    let!(:result) do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov/no_defaults'
        require 'simplecov/formatter/html_formatter'

        SimpleCov.start do
          formatter SimpleCov::Formatter::HTMLFormatter
          command_name "No Defaults"
        end
      RUBY
      run_command_and_expect_success("bundle exec rake test")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "keeps every file the suite loaded" do
      expect(files.length).to eq(6)
    end

    it "keeps the test files" do
      expect(files).to include("test/some_class_test.rb", "test/meta_magic_test.rb")
    end
  end
end
