# frozen_string_literal: true

module SimpleCov
  module CLI
    # `simplecov run <command...>` — exec the given command with
    # simplecov auto-loaded so a coverage report drops into the
    # project's coverage/ directory at the end. Useful for projects
    # without a test_helper that already calls SimpleCov.start (e.g.
    # plain `bundle exec rake test` on an unconfigured library).
    module Run
      AUTOSTART = File.expand_path("../autostart", __dir__)

    module_function

      def run(args, stderr:, **)
        cmd = args.first == "--" ? args.drop(1) : args
        if cmd.empty?
          stderr.puts("simplecov run: missing command")
          return 1
        end

        Kernel.exec(rubyopt_env, *cmd)
      rescue Errno::ENOENT => e
        stderr.puts("simplecov run: #{e.message}")
        127
      end

      def rubyopt_env
        existing = ENV["RUBYOPT"].to_s.strip
        injection = "-r#{AUTOSTART}"
        merged = existing.empty? ? injection : "#{existing} #{injection}"
        ENV.to_hash.merge("RUBYOPT" => merged)
      end
    end
  end
end
