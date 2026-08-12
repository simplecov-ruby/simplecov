# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# The report formatter can be customized via SimpleCov.formatter /
# SimpleCov.formatters: SimpleFormatter returns a plain string of files
# and coverages, and MultiFormatter fans one result out to several
# formatters, surviving (and reporting) individual formatter failures.
RSpec.describe "custom formatters", :sandbox do
  before { setup_project("faked_project") }

  it "prints the SimpleFormatter string via a custom at_exit" do
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

    result = run_command_and_expect_success("bundle exec rake test")
    expect(result.output).to include("lib/faked_project/meta_magic.rb (coverage: 100.0%)")
  end

  it "keeps formatting with the other formatters when one of them fails" do
    # The cucumber feature carried this scenario twice verbatim
    # ("With MultiFormatter" / "With multiple formatters"); once is enough.
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

    result = run_command_and_expect_success("bundle exec rake test")
    expect(result.output).to include("lib/faked_project/meta_magic.rb (coverage: 100.0%)")
    expect(result.output).to match(/Formatter \S* failed with RuntimeError: Unable to format/)
  end
end
