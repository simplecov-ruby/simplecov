# frozen_string_literal: true

module SimpleCov
  #
  # Helper that tries to find out what test suite is running (for SimpleCov.command_name)
  #
  module CommandGuesser
    class << self
      # Storage for the original command line call that invoked the test suite.
      # This has got to be stored as early as possible because i.e. rake and test/unit 2
      # have a habit of tampering with ARGV, which makes i.e. the automatic distinction
      # between rails unit/functional/integration tests impossible without this cached
      # item.
      attr_accessor :original_run_command

      def guess
        [from_command_line_options || from_defined_constants, parallel_data].compact.join(" ")
      end

    private

      def parallel_data
        # If being run from inside parallel_tests set the command name according to the process number
        return unless ENV["PARALLEL_TEST_GROUPS"] && ENV["TEST_ENV_NUMBER"]

        number = ENV.fetch("TEST_ENV_NUMBER", nil)
        number = "1" if number.empty?
        "(#{number}/#{ENV.fetch('PARALLEL_TEST_GROUPS', nil)})"
      end

      COMMAND_LINE_FRAMEWORKS = {
        %r{test/functional/} => "Functional Tests",
        %r{test/\{.*functional.*\}/} => "Functional Tests",
        %r{test/integration/} => "Integration Tests",
        %r{test/} => "Unit Tests",
        /spec/ => "RSpec",
        /cucumber/ => "Cucumber Features",
        /features/ => "Cucumber Features"
      }.freeze
      private_constant :COMMAND_LINE_FRAMEWORKS

      def from_command_line_options
        COMMAND_LINE_FRAMEWORKS.find { |pattern, _| pattern.match?(original_run_command.to_s) }&.last
      end

      # Inner array literals after the first are flagged uncovered by Ruby's
      # Coverage module even though the constant evaluates as a whole — known
      # quirk with multi-line array literals.
      DEFINED_CONSTANT_FRAMEWORKS = [
        ["RSpec",      -> { defined?(::RSpec) }],
        ["Unit Tests", -> { defined?(Test::Unit) }],   # simplecov:disable
        ["Minitest",   -> { defined?(::Minitest) }],   # simplecov:disable
        ["MiniTest",   -> { defined?(MiniTest) }]      # simplecov:disable
      ].freeze
      private_constant :DEFINED_CONSTANT_FRAMEWORKS

      # If the command regexps fail, let's try checking defined constants.
      def from_defined_constants
        # simplecov:disable branch — first iter returns when ::RSpec is defined; later branches unreachable
        DEFINED_CONSTANT_FRAMEWORKS.each { |name, defined_check| return name if defined_check.call }
        # simplecov:enable branch

        # TODO: Provide link to docs/wiki article
        # simplecov:disable — only fires when no framework is detected, which
        # is impossible while our own specs are running under rspec
        warn(
          "SimpleCov failed to recognize the test framework and/or suite used. " \
          "Please specify manually using SimpleCov.command_name 'Unit Tests'."
        )
        "Unknown Test Framework"
        # simplecov:enable
      end
    end
  end
end
