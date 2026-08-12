# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Exit code should be non-zero if the overall coverage is below the
# minimum_coverage threshold.
RSpec.describe "minimum coverage enforcement", :sandbox do
  before { setup_project("faked_project") }

  it "fails against too high coverage" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
        minimum_coverage 90
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include("Line coverage (88.09%) is below the expected minimum coverage (90.00%).")
    expect(result.output).to include("SimpleCov failed with exit 2")
  end

  it "fails if it's just 0.01% too low" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
        minimum_coverage 88.10
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include("Line coverage (88.09%) is below the expected minimum coverage (88.10%).")
    expect(result.output).to include("SimpleCov failed with exit 2")
  end

  it "passes when it is exactly the coverage" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
        minimum_coverage 88.09
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
  end

  it "works together with branch coverage and the new criterion announcing both failures" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
        enable_coverage :branch
        minimum_coverage line: 90, branch: 80
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include("Line coverage (88.09%) is below the expected minimum coverage (90.00%).")
    expect(result.output).to include("Branch coverage (50.00%) is below the expected minimum coverage (80.00%).")
    expect(result.output).to include("SimpleCov failed with exit 2")
  end

  it "can set branch as primary coverage and it will fail if branch is below minimum coverage" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
        enable_coverage :branch
        primary_coverage :branch
        minimum_coverage 80
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include("Branch coverage (50.00%) is below the expected minimum coverage (80.00%).")
    expect(result.output).not_to include("Line coverage (")
    expect(result.output).to include("SimpleCov failed with exit 2")
  end
end
