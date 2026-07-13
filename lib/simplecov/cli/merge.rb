# frozen_string_literal: true

require "json"
require "optparse"

module SimpleCov
  module CLI
    # `simplecov merge <files...>` — wrap SimpleCov::ResultMerger so a
    # CI matrix that produces one .resultset.json per worker can stitch
    # them together from the shell instead of dropping a Rake task into
    # every project. Requires the full simplecov library to be on the
    # load path; lazy-required so the read-only subcommands above don't
    # pay for ResultMerger (and its Coverage runtime guard).
    module Merge
    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        return error(stderr, "missing input files") if opts[:files].empty?
        return 1 unless valid_inputs?(opts[:files], stderr)

        require "simplecov"
        result = SimpleCov::ResultMerger.merge_results(*opts[:files], ignore_timeout: !opts[:honor_timeout])
        return error(stderr, "no mergeable results in input files") unless result

        commit(opts, result, stdout)
        0
      end

      def commit(opts, result, stdout)
        verb = opts[:dry_run] ? "would write" : "wrote"
        write(opts[:output], result) unless opts[:dry_run]
        stdout.puts("simplecov merge: #{verb} #{opts[:output]}") unless opts[:quiet]
      end

      def valid_inputs?(files, stderr)
        parsed = parse_inputs(files, stderr) or return false

        warn_about_duplicate_command_names(parsed, stderr)
        true
      end

      def parse(args)
        opts = {output: SimpleCov::CLI.default_resultset, honor_timeout: false, dry_run: false, quiet: false}
        files =
          OptionParser.new do |o|
            o.on("--output PATH") { |v| opts[:output] = v }
            o.on("--honor-timeout") { opts[:honor_timeout] = true }
            o.on("--dry-run") { opts[:dry_run] = true }
            o.on("-q", "--quiet") { opts[:quiet] = true }
          end.parse(args)
        opts.merge(files: files)
      end

      # Validate every input file up-front and return a {path => parsed}
      # hash. Surfacing per-file errors here turns ResultMerger's
      # generic "no mergeable results" into a message that points at
      # the specific input causing the failure.
      def parse_inputs(files, stderr)
        parsed = {} #: Hash[String, Hash[String, untyped]]
        files.each_with_object(parsed) do |path, memo|
          data = parse_input(path, stderr) or return nil

          memo[path] = data
        end
      end

      def parse_input(path, stderr)
        return parse_input_error(stderr, path, "not found") unless File.exist?(path)

        data = JSON.parse(File.read(path))
        return data if data.is_a?(Hash) && !data.empty?

        parse_input_error(stderr, path, "has no resultset entries")
      rescue JSON::ParserError => e
        parse_input_error(stderr, path, "isn't valid JSON (#{e.message})")
      end

      def parse_input_error(stderr, path, reason)
        stderr.puts("simplecov merge: input file #{path.inspect} #{reason}")
        nil
      end

      # When two input files share a command_name, ResultMerger folds
      # them together with last-write-wins on the timestamp — easy to
      # mistake for "no merge happened." Surface the overlap so the
      # operator can rename the workers or accept the merge knowingly.
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
        require "fileutils"
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(result.to_hash))
      end

      def error(stderr, message)
        stderr.puts("simplecov merge: #{message}")
        1
      end
    end
  end
end
