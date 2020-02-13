# frozen_string_literal: true

module CLIAcceptance
module_function

  def dispatch(argv)
    command, *args = argv

    command ||= "c"

    case command.downcase
    when "greet" then greet(args.first)
    when "add" then add(args)
    else
      wait_what(command)
    end
  end

  def greet(name)
    puts "Hello there #{name}"
  end

  def add(args)
    sum = args.map(&:to_i).sum
    puts sum
  end

  def wait_what(command_name)
    puts "Sorry, can't understand #{command_name}"
  end

  def echo_two(args = nil)
    if args.nil? || Array(args).empty?
      2
    else
      args
    end
  end
end
