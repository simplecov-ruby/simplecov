# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Exit code should be non-zero if the overall coverage is either above
# or below the expected_coverage threshold. Useful for pinning coverage
# to an exact value so unexpected improvements (which should bump the
# threshold) don't slip through silently. See issue #187.
RSpec.describe "expected coverage enforcement", :sandbox do
  before { setup_project("faked_project") }

  it "passes when the actual coverage matches exactly" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
        expected_coverage 88.09
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
  end

  it "fails when actual coverage is below" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
        expected_coverage 90
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include("Line coverage (88.09%) is below the expected minimum coverage (90.00%).")
    expect(result.output).to include("SimpleCov failed with exit 2")
  end

  it "fails when actual coverage is above" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
        expected_coverage 80
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include("Line coverage (88.09%) is above the expected maximum coverage (80.00%).")
    expect(result.output).to include("Time to bump the threshold!")
    expect(result.output).to include("SimpleCov failed with exit 4")
  end

  it "fails when actual is above maximum_coverage on its own" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
        maximum_coverage 85
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include("Line coverage (88.09%) is above the expected maximum coverage (85.00%).")
    expect(result.output).to include("SimpleCov failed with exit 4")
  end
end
