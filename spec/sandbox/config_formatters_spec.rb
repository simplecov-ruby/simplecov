# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "custom formatters", :sandbox do
  before { setup_project("faked_project") }

  describe "the SimpleFormatter under a custom at_exit" do
    let!(:result) do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.formatter = SimpleCov::Formatter::SimpleFormatter
        SimpleCov.at_exit do
          puts SimpleCov.result.format!
        end
        SimpleCov.start do
          add_group 'Libs', 'lib/faked_project/'
        end
      RUBY
      run_command_and_expect_success("bundle exec rake test")
    end

    it "prints the formatted string" do
      expect(result.output).to include("lib/faked_project/meta_magic.rb (coverage: 100.0%)")
    end
  end

  describe "one formatter of several failing" do
    let!(:result) do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.formatters = [
          SimpleCov::Formatter::SimpleFormatter,
          Class.new do
            def format(result)
              raise "Unable to format"
            end
          end
        ]

        SimpleCov.at_exit do
          puts SimpleCov.result.format!.join
        end
        SimpleCov.start do
          add_group 'Libs', 'lib/faked_project/'
        end
      RUBY
      run_command_and_expect_success("bundle exec rake test")
    end

    it "keeps formatting with the others" do
      expect(result.output).to include("lib/faked_project/meta_magic.rb (coverage: 100.0%)")
    end

    it "names the one that failed" do
      expect(result.output).to match(/Formatter \S* failed with RuntimeError: Unable to format/)
    end
  end
end
