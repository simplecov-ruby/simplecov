# frozen_string_literal: true

require "optparse"
require_relative "command_helpers"
require_relative "usage"
require_relative "completions/scripts"

module SimpleCov
  module CLI
    # `simplecov completions <shell>` — completion scripts for fish,
    # bash, and zsh. Generated from the usage document rather than a
    # hand-kept table: the Commands list provides the subcommands and
    # their descriptions, and each command's options sections provide
    # its flags, so a new command or switch shows up in completions the
    # moment it is documented.
    module Completions
      extend CommandHelpers

    module_function

      SHELLS = %w[fish bash zsh].freeze

      # "  -q, --quiet               Suppress..." — optional short,
      # long, optional argument placeholder, then the description after
      # the column gap. A single space never separates the switch from
      # its description, so one non-space token before a two-space run
      # can only be an argument.
      OPTION_ROW = /\A\s*(?:(-\w), )?(--[\w-]+)(?: (\S+))?\s{2,}(\S.*)\z/
      # "  watch <command...>        Re-run..." — the name, any
      # argument placeholders, then the description after the gap.
      COMMAND_ROW = /\A(\S+)(?: \S+)*?\s{2,}(\S.*)\z/

      def run(args, stdout:, stderr:)
        shell, = OptionParser.new { |parser| on_help(parser) }.parse(args)
        return error(stderr, "missing shell (expected fish, bash, or zsh)") unless shell
        unless SHELLS.include?(shell)
          return error(stderr, "unknown shell #{shell.inspect} (expected fish, bash, or zsh)")
        end

        stdout.puts(script_for(shell))
        0
      end

      def script_for(shell)
        case shell
        when "fish" then Scripts.fish(commands, options_by_command)
        when "bash" then Scripts.bash(commands, options_by_command)
        else Scripts.zsh(commands, options_by_command)
        end
      end

      def commands
        Usage.text(SimpleCov::CLI).split("\n\n").fetch(1).lines.drop(1).filter_map do |row|
          match = row.strip.match(COMMAND_ROW)
          match && [(_ = match[1]), (_ = match[2])]
        end
      end

      def options_by_command
        commands.filter_map do |name, _desc|
          list = options_for(name)
          [name, list] unless list.empty?
        end.to_h
      end

      # `run` takes no options of its own (everything after it belongs
      # to the command being run), so it must not even offer --help.
      def options_for(command)
        return [] if command == "run"

        sections = Usage.text(SimpleCov::CLI).split("\n\n").select { |section| Usage.section_for?(section, command) }
        options = sections.flat_map { |section| section_options(section) }
        options << {short: "-h", long: "--help", arg: nil, desc: "Show this command's usage"}
      end

      # Rows that don't parse as options are continuations of the
      # previous row's description, wrapped for the terminal.
      def section_options(section)
        section.lines.drop(1).each_with_object([]) do |line, options|
          if (match = line.chomp.match(OPTION_ROW))
            options << {short: match[1], long: match[2], arg: match[3], desc: (_ = match[4])}
          elsif options.last
            options.last[:desc] = "#{options.last[:desc]} #{line.strip}"
          end
        end
      end
    end
  end
end
