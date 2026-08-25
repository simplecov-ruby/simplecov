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
    # The default view prints the bottom two rows (the deletion
    # candidates); `--untested-in-production` prints the second (the
    # highest-value place to add a test). Coverage over a long enough
    # window is far better evidence for deleting Ruby than any static
    # analysis of it, which is why the header names the window the
    # production data spans.
    module DeadCode
      extend CommandHelpers

    module_function

      # The module-name derivation would say "deadcode"; the command is
      # hyphenated.
      def command_name
        "dead-code"
      end

      def run(args, stdout:, stderr:, **)
        opts = parse(args, stderr) or return 1
        coverage = CoverageFile.load_coverage(opts[:input], command: command_name, stderr: stderr) or return 1
        production = load_production(opts[:production], stderr) or return 1

        matrix = cross(coverage, production.fetch("coverage"))
        Output.emit(stdout, opts, matrix, production)
        0
      end

      def parse(args, stderr)
        opts, rest = parse_common(args, production: nil, untested: false) do |parser, options|
          parser.on("--production PATH") { |v| options[:production] = v }
          parser.on("--untested-in-production") { options[:untested] = true }
        end
        return error_nil(stderr, "unexpected argument #{rest.first.inspect}") unless rest.empty?
        unless opts[:production]
          return error_nil(stderr,
                           "missing --production PATH (the file a SimpleCov::Production sink wrote)")
        end

        opts
      end

      def load_production(path, stderr)
        Production::FileSink.read(path)
      rescue Errno::ENOENT
        error_nil(stderr, "#{path} not found")
      rescue SystemCallError, Production::Error => e
        error_nil(stderr, e.message)
      end

      # Classify every relevant line of the report against the
      # production set, and sweep in production files the report never
      # tracked (nothing tested them, so every recorded line is
      # untested-in-production). Lines the report deems irrelevant or
      # deliberately ignored stay out of every bucket.
      def cross(coverage, production_coverage)
        matrix = {dead: {}, possibly_dead: {}, untested_in_production: {}, entire: Set.new} #: Hash[Symbol, untyped]
        coverage.each do |file, entry|
          lines = entry["lines"]
          classify_file(matrix, file, lines, production_coverage[file] || []) if lines.is_a?(Array)
        end
        (production_coverage.keys - coverage.keys).sort.each do |file|
          matrix[:untested_in_production][file] = production_coverage[file].sort
        end
        matrix
      end

      def classify_file(matrix, file, lines, production_lines)
        production = production_lines.to_set
        buckets = {dead: [], possibly_dead: [], untested_in_production: []} #: Hash[Symbol, Array[Integer]]
        relevant = 0
        lines.each_with_index do |value, index|
          next unless value.is_a?(Numeric)

          relevant += 1
          bucket = classify_line(value.positive?, production.include?(index + 1))
          buckets[bucket] << (index + 1) if bucket
        end
        record(matrix, file, buckets, relevant)
      end

      # The matrix's four cells; the yes/yes cell is the one nothing
      # needs reporting about.
      def classify_line(tested, in_production)
        if in_production
          tested ? nil : :untested_in_production
        else
          tested ? :possibly_dead : :dead
        end
      end

      def record(matrix, file, buckets, relevant)
        buckets.each { |bucket, found| matrix[bucket][file] = found unless found.empty? }
        return unless relevant.positive? && buckets[:dead].size + buckets[:possibly_dead].size == relevant

        # Every relevant line unhit in production: the deletion
        # candidate is the whole file, and the report says so.
        matrix[:entire] << file
      end
    end
  end
end
