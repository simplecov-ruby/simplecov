# So much skippping
# rubocop:disable Metrics/MethodLength
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
# rubocop:enable Metrics/MethodLength
