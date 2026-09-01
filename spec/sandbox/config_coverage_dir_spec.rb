# frozen_string_literal: true

require "helper"
require "support/sandbox_project"
require "tmpdir"

RSpec.describe "custom coverage directory", :sandbox do
  before { setup_project("faked_project") }

  describe "a relative custom directory" do
    let!(:result) do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          coverage_dir 'test/simplecov'
        end
      RUBY
      run_command_and_expect_success("bundle exec rake test")
    end

    it "holds the report" do
      expect_coverage_report_generated(result, coverage_dir: "test/simplecov")
    end

    it "leaves the default directory alone" do
      expect(file_exist?("coverage")).to be(false)
    end
  end

  describe "an absolute custom directory" do
    let(:tmp_root) { File.join(Dir.tmpdir, "simplecov-sandbox-#{Process.pid}") }
    let(:absolute_dir) { File.join(tmp_root, "test", "simplecov") }
    let!(:result) do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          coverage_dir '#{absolute_dir}'
        end
      RUBY
      run_command_and_expect_success("bundle exec rake test")
    end

    after { FileUtils.rm_rf(tmp_root) }

    it "announces the report" do
      expect(result.output).to include("Coverage report generated")
    end

    it "holds the HTML report" do
      expect(File.exist?(File.join(absolute_dir, "index.html"))).to be(true)
    end

    it "holds the resultset" do
      expect(File.exist?(File.join(absolute_dir, ".resultset.json"))).to be(true)
    end

    it "leaves the default directory alone" do
      expect(file_exist?("coverage")).to be(false)
    end
  end
end
