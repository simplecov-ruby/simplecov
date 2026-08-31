# frozen_string_literal: true

require "fileutils"
require "optparse"
require_relative "command_helpers"

module SimpleCov
  module CLI
    # `simplecov clean [--dry-run]`: remove the coverage report directory.
    # `--dry-run` prints what would be deleted without touching disk.
    module Clean
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        dir = CLI.coverage_dir
        return error(stderr, "refusing to remove unsafe coverage directory #{dir.inspect}") unless safe_to_remove?(dir)
        return announce(stdout, opts, "#{dir} doesn't exist; nothing to do") || 0 unless File.directory?(dir)

        sweep(dir, opts, stdout)
        0
      end

      def sweep(dir, opts, stdout)
        if opts.fetch(:dry_run)
          announce(stdout, opts, "would remove #{dir} (#{entry_count(dir)} entries)")
        else
          FileUtils.rm_rf(dir)
          announce(stdout, opts, "removed #{dir}")
        end
      end

      # FNM_DOTMATCH so the dotfiles rm_rf will actually delete count too. The
      # glob still yields the directory's own "." entry, which rm_rf does not
      # remove separately.
      def entry_count(dir)
        Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).count { |path| !path.end_with?("/.") }
      end

      def announce(stdout, opts, message)
        stdout.puts("simplecov #{command_name}: #{message}") unless opts.fetch(:quiet)
      end

      # A filesystem root is its own dirname, on every platform and every Windows
      # drive. The descendant check only protects roots that happen to contain the
      # cwd, which misses other drives, so roots are refused outright.
      def safe_to_remove?(dir)
        target = canonical_path(dir)
        return false if File.dirname(target).eql?(target)

        protected_paths.none? { |path| path.eql?(target) || descendant_of?(path, target) }
      end

      # The working directory, which a coverage directory must not be or contain.
      # The `.simplecov` project root needs no entry of its own: `Dotfile.find`
      # walks up from the working directory, so any target containing that root
      # contains the working directory too.
      def protected_paths
        [canonical_path(Dir.pwd)]
      end

      # Canonical paths only carry a trailing separator on a filesystem root, and
      # roots are refused before this check runs.
      def descendant_of?(path, possible_ancestor)
        path.start_with?("#{possible_ancestor}#{File::SEPARATOR}")
      end

      def canonical_path(path)
        File.realpath(path)
      rescue SystemCallError
        File.expand_path(path)
      end

      def parse(args)
        opts = {dry_run: false, quiet: false}
        build_parser do |o|
          o.on("--dry-run") { opts[:dry_run] = true }
          quiet_option(o, opts)
        end.parse(args)
        opts
      end
    end
  end
end
