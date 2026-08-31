# frozen_string_literal: true

require_relative "command_helpers"
require_relative "coverage_file"
require_relative "../production/file_sink"
require_relative "dead_code/output"

module SimpleCov
  module CLI
    # `simplecov dead-code --production PATH` — cross the coverage a
    # `SimpleCov::Production` sink accumulated with the test report, and
    # answer the question neither answers alone. Per line:
    #
    #   production | tests | meaning
    #   yes        | yes   | normal
    #   yes        | no    | untested code real users are running
    #   no         | yes   | possibly dead, a deletion candidate
    #   no         | no    | dead
    #
    # The default view prints the bottom two rows (the deletion candidates);
    # `--untested-in-production` prints the second (the highest-value place to
    # add a test). Coverage over a long enough window is far better evidence
    # for deleting Ruby than any static analysis of it, which is why the header
    # names the window the production data spans.
    module DeadCode
      extend CommandHelpers

      extend self

      # The module-name derivation would say "deadcode"; the command is
      # hyphenated.
      def command_name
        "dead-code"
      end

      def run(args, stdout:, stderr:, **)
        opts = parse(args, stderr) or return 1
        coverage = CoverageFile.load_coverage(opts.fetch(:input), command: command_name, stderr: stderr) or return 1
        production = load_production(opts.fetch(:production), stderr) or return 1

        matrix = cross(coverage, production.fetch("coverage"))
        Output.emit(stdout, opts, matrix, production)
        0
      end

      def parse(args, stderr)
        # `production` needs no default: it is filled in below from the project's
        # configured store whenever the flag went unused.
        opts, rest = parse_common(args, untested: false) do |parser, options|
          parser.on("--production PATH") { |v| options[:production] = v }
          parser.on("--untested-in-production") { options[:untested] = true }
        end
        return error_nil(stderr, "unexpected argument #{rest.first.inspect}") unless rest.empty?

        # The project's configured store fills in for the flag, the way ratchet
        # reads `baseline_file`, so the DSL stays the single source of truth for
        # where production coverage lives.
        opts[:production] ||= Dotfile.production_coverage
        opts.fetch(:production) ? opts : missing_production(stderr)
      end

      def missing_production(stderr)
        error_nil(stderr,
                  "missing --production PATH (the file a SimpleCov::Production sink wrote, " \
                  "or configure SimpleCov.production_coverage in .simplecov)")
      end

      def load_production(path, stderr)
        Production::FileSink.read(path)
      rescue Errno::ENOENT
        error_nil(stderr, "#{path} not found")
      rescue SystemCallError, Production::Error => e
        # The exception stands for its own message in `error`'s interpolation.
        error_nil(stderr, e)
      end

      # Classifies every relevant line of the report against the production set,
      # and sweeps in production files the report never tracked (nothing tested
      # them, so every recorded line is untested-in-production). Lines the
      # report deems irrelevant or deliberately ignored stay out of every
      # bucket.
      def cross(coverage, production_coverage)
        matrix = {dead: {}, possibly_dead: {}, untested_in_production: {}, entire: Set.new} #: Hash[Symbol, untyped]
        coverage.each do |file, entry|
          lines = entry["lines"]
          classify_file(matrix, file, lines, production_coverage[file] || []) if lines.instance_of?(Array)
        end
        # Files go in unsorted: both the text sections and the JSON payload sort
        # what they print.
        (production_coverage.keys - coverage.keys).each do |file|
          matrix.fetch(:untested_in_production)[file] = production_coverage.fetch(file).sort
        end
        matrix
      end

      # mutant:disable -- the production lines are held as a Set for the cost of
      # asking, and a list answers `include?` the same way, so the conversion
      # has no witness at any call site it could live at.
      def classify_file(matrix, file, lines, production_lines)
        production = production_lines.to_set
        buckets = {dead: [], possibly_dead: [], untested_in_production: []} #: Hash[Symbol, Array[Integer]]
        relevant = 0
        lines.each_with_index do |value, index|
          next unless value.is_a?(Numeric)

          relevant += 1
          bucket = classify_line(value.positive?, production.include?(index + 1))
          buckets.fetch(bucket) << (index + 1) if bucket
        end
        record(matrix, file, buckets, relevant)
      end

      # The matrix's four cells; the yes/yes cell is the one nothing needs
      # reporting about.
      def classify_line(tested, in_production)
        return :untested_in_production if in_production && !tested
        return nil if in_production

        tested ? :possibly_dead : :dead
      end

      # mutant:disable -- the count of relevant lines is checked before a file is
      # called entirely dead, but a file with no relevant lines lands in no
      # bucket, so the mark is never read back. The guard says what is meant
      # rather than what can be seen.
      def record(matrix, file, buckets, relevant)
        buckets.each { |bucket, found| matrix.fetch(bucket)[file] = found unless found.empty? }
        # Counted down to nothing rather than compared for equality: two counts
        # that are equal are equal through every spelling of the comparison.
        unhit = buckets.fetch(:dead).size + buckets.fetch(:possibly_dead).size
        return unless relevant.positive? && (relevant - unhit).zero?

        # Every relevant line unhit in production: the deletion candidate is the
        # whole file.
        matrix.fetch(:entire) << file
      end
    end
  end
end
