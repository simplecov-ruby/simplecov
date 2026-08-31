# frozen_string_literal: true

module SimpleCov
  module CommandGuesser
    class << self
      # The original command line call that invoked the test suite. This has to
      # be stored as early as possible because rake and test/unit 2 have a habit
      # of tampering with ARGV.
      attr_reader :original_run_command

      # Assigning the flattened command clears any separately recorded program
      # name so the two can never describe different runs. Callers that know the
      # real one assign it immediately afterwards, as `defaults.rb` does.
      def original_run_command=(command)
        @original_program_name = nil
        @original_run_command = command
      end

      # The invoked program on its own. `original_run_command` joins
      # `$PROGRAM_NAME` and `ARGV` with a space, so a program path containing
      # one (`/opt/My Ruby/bin/rspec`) cannot be recovered from it afterwards.
      # Falls back to the first token for callers that set only the flattened
      # command, which is every caller outside `defaults.rb`.
      attr_writer :original_program_name

      def original_program_name
        @original_program_name || original_run_command.to_s[/\A\s*(\S+)/, 1]
      end

      def guess
        framework = from_executable_name || from_command_line_options || from_defined_constants
        [framework, parallel_data].compact.join(" ")
      end

    private

      # When parallel_tests (or a compatible runner) is driving the suite, tag
      # the command name with this worker's position in the pool.
      def parallel_data
        groups, number = ENV.values_at("PARALLEL_TEST_GROUPS", "TEST_ENV_NUMBER")
        return unless groups && number

        # parallel_tests sets the first worker's TEST_ENV_NUMBER to "" rather
        # than "1"; restore the position so the rendered label reads cleanly.
        number = "1" if number.empty?
        "(#{number}/#{groups})"
      end

      # The command is `"#{$PROGRAM_NAME} #{ARGV.join(' ')}"`, so a keyword only
      # carries meaning when it begins a path segment or an argument. Matching
      # it as a bare substring lets any part of the interpreter path decide the
      # suite name: a Ruby installed under `latest/bin` (as mise does) contains
      # "test/", so every run through it was labelled "Unit Tests".
      #
      # A backslash bounds a segment too, or a Windows `spec\foo_spec.rb` would
      # lose a match. The `test/` patterns below still spell their separator as
      # `/` only, which is how it has always been.
      SEGMENT_START = %r{(?<![^\s/\\])}
      private_constant :SEGMENT_START
      SEGMENT_END = %r{(?=[\s/\\]|\z)}
      private_constant :SEGMENT_END

      COMMAND_LINE_FRAMEWORKS = {
        %r{#{SEGMENT_START}test/functional/} => "Functional Tests",
        %r{#{SEGMENT_START}test/\{.*functional.*\}/} => "Functional Tests",
        %r{#{SEGMENT_START}test/integration/} => "Integration Tests",
        %r{#{SEGMENT_START}test/} => "Unit Tests",
        /#{SEGMENT_START}spec#{SEGMENT_END}/ => "RSpec",
        /#{SEGMENT_START}cucumber#{SEGMENT_END}/ => "Cucumber Features",
        /#{SEGMENT_START}features#{SEGMENT_END}/ => "Cucumber Features"
      }.freeze
      private_constant :COMMAND_LINE_FRAMEWORKS

      def from_command_line_options
        # A command that was never recorded matches nothing, which `match?`
        # answers for a nil of its own accord.
        COMMAND_LINE_FRAMEWORKS.find { |pattern, _| pattern.match?(original_run_command) }&.last
      end

      # Which binary was invoked outranks everything else on the command line.
      # `rspec features` is an RSpec suite whose examples live in features/, not
      # a Cucumber run, and only the executable name says so. Generic runners
      # (`ruby`, `rake`, a bare `*_test.rb` script) are absent on purpose: they
      # name no framework, so those runs fall through to the path patterns.
      EXECUTABLE_FRAMEWORKS = {
        "rspec" => "RSpec",
        "cucumber" => "Cucumber Features"
      }.freeze
      private_constant :EXECUTABLE_FRAMEWORKS

      def from_executable_name
        program = original_program_name
        return unless program

        # The extension is trimmed so Windows' rspec.bat is recognized too.
        EXECUTABLE_FRAMEWORKS[File.basename(program, ".*")]
      end

      # Inner array literals after the first are flagged uncovered by Ruby's
      # Coverage module even though the constant evaluates as a whole, a known
      # quirk with multi-line array literals.
      DEFINED_CONSTANT_FRAMEWORKS = [
        ["RSpec",      -> { defined?(::RSpec) }],
        ["Unit Tests", -> { defined?(Test::Unit) }],   # simplecov:disable
        ["Minitest",   -> { defined?(::Minitest) }],   # simplecov:disable
        ["MiniTest",   -> { defined?(MiniTest) }]      # simplecov:disable
      ].freeze
      private_constant :DEFINED_CONSTANT_FRAMEWORKS

      def from_defined_constants
        DEFINED_CONSTANT_FRAMEWORKS.each { |name, defined_check| return name if defined_check.call }

        warn(
          "SimpleCov failed to recognize the test framework and/or suite used. " \
          "Please specify manually using SimpleCov.command_name 'Unit Tests'."
        )
        "Unknown Test Framework"
      end
    end
  end
end
