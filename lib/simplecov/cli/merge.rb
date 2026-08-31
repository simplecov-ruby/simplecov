# frozen_string_literal: true

require "json"
require "optparse"
require_relative "../atomic_file"
require_relative "command_helpers"

module SimpleCov
  module CLI
    # `simplecov merge <files...>`: wraps `SimpleCov::ResultMerger` so a CI
    # matrix that produces one .resultset.json per worker can stitch them
    # together from the shell instead of dropping a Rake task into every project.
    module Merge
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        return error(stderr, "missing input files") if opts.fetch(:files).empty?

        parsed = parse_inputs(opts.fetch(:files), stderr)
        return 1 unless parsed

        warn_about_duplicate_command_names(parsed, stderr)
        result = result_merger.merge_results(*opts.fetch(:files), ignore_timeout: !opts.fetch(:honor_timeout))
        return error(stderr, "no mergeable results in input files") unless result

        commit(opts, result, stdout)
        0
      end

      # Loaded here rather than at the top of the file, so the read-only
      # subcommands never pay for ResultMerger and its Coverage runtime guard.
      def result_merger
        require "simplecov"
        ResultMerger
      end

      def commit(opts, result, stdout)
        verb = opts.fetch(:dry_run) ? "would write" : "wrote"
        write(opts.fetch(:output), result) unless opts.fetch(:dry_run)
        stdout.puts("simplecov merge: #{verb} #{opts.fetch(:output)}") unless opts.fetch(:quiet)
      end

      def parse(args)
        opts = {output: CLI.default_resultset, honor_timeout: false, dry_run: false, quiet: false}
        files =
          build_parser do |o|
            o.on("--output PATH") { |v| opts[:output] = v }
            o.on("--honor-timeout") { opts[:honor_timeout] = true }
            o.on("--dry-run") { opts[:dry_run] = true }
            quiet_option(o, opts)
          end.parse(args)
        opts.merge(files: files)
      end

      # Validating every input up front turns ResultMerger's generic "no mergeable
      # results" into a message that points at the specific input causing it.
      def parse_inputs(files, stderr)
        parsed = {} #: Hash[String, Hash[String, untyped]]
        files.each_with_object(parsed) do |path, memo|
          data = parse_input(path, stderr) or return nil

          memo[path] = data
        end
      end

      # Read first and classify by the exception: an exist?-then-read pair is racy,
      # and rescuing only ENOENT crashed with a backtrace on a directory or an
      # unreadable file.
      def parse_input(path, stderr)
        data = JSON.parse(File.read(path))
        return data if data.instance_of?(Hash) && !data.empty?

        parse_input_error(stderr, path, "has no resultset entries")
      rescue Errno::ENOENT
        parse_input_error(stderr, path, "not found")
      rescue JSON::ParserError => e
        parse_input_error(stderr, path, "isn't valid JSON (#{e})")
      rescue SystemCallError => e
        parse_input_error(stderr, path, "cannot be read (#{e.message.lines.first.to_s.rstrip})")
      end

      def parse_input_error(stderr, path, reason)
        stderr.puts("simplecov merge: input file #{path.inspect} #{reason}")
      end

      # ResultMerger folds entries that share a command_name together with
      # last-write-wins on the timestamp, which is easy to mistake for "no merge
      # happened", so the overlap is surfaced.
      def warn_about_duplicate_command_names(parsed, stderr)
        files_per_command = {} #: Hash[String, Array[String]]
        parsed.each do |path, data|
          data.each_key { |command_name| (files_per_command[command_name] ||= []) << path }
        end
        files_per_command.each do |command_name, paths|
          next if paths.size < 2

          stderr.puts(duplicate_warning(command_name, paths))
        end
      end

      def duplicate_warning(command_name, paths)
        "simplecov merge: warning — command_name #{command_name.inspect} " \
          "appears in #{paths.size} input files (#{paths.join(', ')}); " \
          "entries will be merged"
      end

      def write(path, result)
        AtomicFile.write(path, JSON.pretty_generate(result.to_hash))
      end
    end
  end
end
