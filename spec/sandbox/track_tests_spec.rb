# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# `track_tests` records which test covered which line by peeking at
# coverage around each example, and stores the map in `.resultset.json`
# beside the merged coverage: an interned test list plus per-file hex
# bitmaps keyed by test index.
RSpec.describe "track_tests", :sandbox do
  before { setup_project("faked_project") }

  def stored_contexts
    resultset = resultset_json
    expect(resultset.size).to eq(1)
    map = resultset.values.first["contexts"]
    expect(map).not_to be_nil
    SimpleCov::ContextMap.from_hash(map)
  end

  it "records each RSpec example against the lines it covered" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        track_tests
      end
    RUBY

    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)

    map = stored_contexts
    expect(map.contexts).to include(match(%r{\Aspec/some_class_spec\.rb:\d+\z}))

    # SomeClass#reverse's body is line 12 of some_class.rb, and the
    # "should be reversible" example is what drives it.
    reversible = File.join(sandbox_dir, "lib/faked_project/some_class.rb")
    expect(map.covering(reversible, 12)).to include(match(%r{\Aspec/some_class_spec\.rb:\d+\z}))
  end

  it "records each Minitest test against the lines it covered" do
    self.bundle_with = "minitest"
    install_dependencies
    configure_simplecov(:minitest, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        track_tests
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake minitest")
    expect_coverage_report_generated(result)

    map = stored_contexts
    expect(map.contexts).to include(match(%r{\Aminitest/some_test\.rb:\d+\z}))
  end
end
