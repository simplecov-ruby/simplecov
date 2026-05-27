# frozen_string_literal: true

require "optparse"

module SimpleCov
  module CLI
    # `simplecov clean [--dry-run]` — remove the coverage report
    # directory (or whatever `SimpleCov.coverage_dir` resolves to). The
    # `--dry-run` flag prints what would be deleted without touching
    # disk, for when you're not sure what's in there.
    module Clean
    module_function

      def run(args, stdout:, **)
        opts = parse(args)
        dir = SimpleCov::CLI.coverage_dir
        return announce(stdout, opts, "#{dir} doesn't exist; nothing to do") || 0 unless File.directory?(dir)

        sweep(dir, opts, stdout)
        0
      end

      def sweep(dir, opts, stdout)
        if opts[:dry_run]
          announce(stdout, opts, "would remove #{dir} (#{Dir["#{dir}/**/*"].size} entries)")
        else
          require "fileutils"
          FileUtils.rm_rf(dir)
          announce(stdout, opts, "removed #{dir}")
        end
      end

      def announce(stdout, opts, message)
        stdout.puts("simplecov clean: #{message}") unless opts[:quiet]
      end

      def parse(args)
        opts = {dry_run: false, quiet: false}
        OptionParser.new do |o|
          o.on("--dry-run") { opts[:dry_run] = true }
          o.on("-q", "--quiet") { opts[:quiet] = true }
        end.parse(args)
        opts
      end
    end
  end
end
