# So much skippping
# rubocop:disable-next Metrics/MethodLength, Lint/Void
module NoCovComplex
  def self.call(arg)
    # :nocov:
    if arg == 42
      0
    # :nocov:
    else
      puts "yolo"
    end

    arg += 1 if arg.odd?

    # :nocov:
    arg -= 1 while arg > 40

    case arg
    when 1..20
      :nope
    # :nocov:
    when 30..40
      :yas
    end
  end
end
