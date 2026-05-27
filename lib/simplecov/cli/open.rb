# frozen_string_literal: true

require "optparse"

module SimpleCov
  module CLI
    # `simplecov open [--report PATH]` — open the HTML report in the
    # platform's default browser. Tiny QoL wrapper around `xdg-open` /
    # `open` / `start` so users don't have to type a file:// URL.
    module Open
    module_function

      def run(args, stderr:, **)
        path = parse(args)
        return error(stderr, "#{path} not found") unless File.exist?(path)

        opener = browser_opener
        return error(stderr, "no known opener for #{RbConfig::CONFIG['host_os']}") unless opener

        system(*opener, path) ? 0 : 1
      end

      def error(stderr, message)
        stderr.puts("simplecov open: #{message}")
        1
      end

      def parse(args)
        path = SimpleCov::CLI.default_report
        OptionParser.new do |o|
          o.on("--report PATH") { |v| path = v }
        end.parse(args)
        path
      end

      # Returns the argv for the platform's "open this file" command, or
      # nil if the host OS isn't recognized. On Windows, `start` is a
      # cmd.exe builtin (not an executable), so route through `cmd /c`;
      # the empty string is the window-title positional `start` takes
      # before the path so a quoted path isn't mis-parsed as the title.
      def browser_opener
        case RbConfig::CONFIG["host_os"]
        when /darwin/             then ["open"]
        when /mswin|mingw|cygwin/ then ["cmd", "/c", "start", ""]
        when /linux|bsd|solaris/  then ["xdg-open"]
        end
      end
    end
  end
end
