# frozen_string_literal: true

module SimpleCov
  module CLI
    module Run
      AUTOSTART = File.expand_path("../autostart", __dir__.to_s)

      extend self

      def run(args, stderr:, **)
        cmd = args.first.eql?("--") ? args.drop(1) : args
        if cmd.empty?
          stderr.puts("simplecov run: missing command")
          return 1
        end

        exec_command(rubyopt_env, cmd)
      rescue Errno::ENOENT => e
        stderr.puts("simplecov run: #{e}")
        127
      end

      def exec_command(env, cmd)
        Kernel.exec(env, *cmd)
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
