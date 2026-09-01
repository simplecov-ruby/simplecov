# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "track_tests", :sandbox do
  let(:tracking_config) do
    <<~RUBY
      require 'simplecov'
      SimpleCov.start do
        track_tests
      end
    RUBY
  end

  before { setup_project("faked_project") }

  def stored_contexts
    resultset = resultset_json
    expect(resultset.size).to eq(1)
    map = resultset.values.first["contexts"]
    expect(map).not_to be_nil
    SimpleCov::ContextMap.from_hash(map)
  end

  describe "an RSpec suite" do
    let!(:result) do
      configure_simplecov(:rspec, tracking_config)
      run_command_and_expect_success(sorted_rspec_command)
    end
    let(:some_class) { File.join(sandbox_dir, "lib/faked_project/some_class.rb") }

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "records each example as a context" do
      expect(stored_contexts.contexts).to include(match(%r{\Aspec/some_class_spec\.rb:\d+\z}))
    end

    it "records each example against the lines it covered" do
      expect(stored_contexts.covering(some_class, 12)).to include(match(%r{\Aspec/some_class_spec\.rb:\d+\z}))
    end
  end

  describe "a Minitest suite" do
    let!(:result) do
      self.bundle_with = "minitest"
      install_dependencies
      configure_simplecov(:minitest, tracking_config)
      run_command_and_expect_success("bundle exec rake minitest")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "records each test as a context" do
      expect(stored_contexts.contexts).to include(match(%r{\Aminitest/some_test\.rb:\d+\z}))
    end
  end
end
