# frozen_string_literal: true

require "optparse"
require_relative "command_helpers"

module SimpleCov
  module CLI
    # `simplecov clean [--dry-run]` — remove the coverage report
    # directory (or whatever `SimpleCov.coverage_dir` resolves to). The
    # `--dry-run` flag prints what would be deleted without touching
    # disk, for when you're not sure what's in there.
    module Clean
      extend CommandHelpers

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        dir = SimpleCov::CLI.coverage_dir
        return error(stderr, "refusing to remove unsafe coverage directory #{dir.inspect}") unless safe_to_remove?(dir)
        return announce(stdout, opts, "#{dir} doesn't exist; nothing to do") || 0 unless File.directory?(dir)

        sweep(dir, opts, stdout)
        0
      end

      def sweep(dir, opts, stdout)
        if opts[:dry_run]
          announce(stdout, opts, "would remove #{dir} (#{entry_count(dir)} entries)")
        else
          require "fileutils"
          FileUtils.rm_rf(dir)
          announce(stdout, opts, "removed #{dir}")
        end
      end

      # FNM_DOTMATCH so the dotfiles rm_rf will actually delete
      # (.resultset.json, .last_run.json) count too; the glob still
      # yields the directory's own "." entry, which rm_rf does not
      # remove separately.
      def entry_count(dir)
        Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).count { |path| !path.end_with?("/.") }
      end

      def announce(stdout, opts, message)
        stdout.puts("simplecov #{command_name}: #{message}") unless opts[:quiet]
      end

      def safe_to_remove?(dir)
        target = canonical_path(dir)
        # A filesystem root is its own dirname ("/" everywhere, drive
        # roots like "D:/" on Windows). The descendant check below only
        # protects roots that happen to contain the cwd or project root,
        # which misses other drives, so refuse roots outright.
        return false if File.dirname(target) == target

        protected_paths.none? { |path| path == target || descendant_of?(path, target) }
      end

      def protected_paths
        project_root = SimpleCov::CLI::Dotfile.find
        [Dir.pwd, (File.dirname(project_root) if project_root)].compact.map { |path| canonical_path(path) }.uniq
      end

      # Canonical paths only carry a trailing separator on a filesystem
      # root, and roots are refused before this check runs.
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
        OptionParser.new do |o|
          o.on("--dry-run") { opts[:dry_run] = true }
          o.on("-q", "--quiet") { opts[:quiet] = true }
          on_help(o)
        end.parse(args)
        opts
      end
    end
  end
end
