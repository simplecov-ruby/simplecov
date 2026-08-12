# So much skippping
# rubocop:disable Metrics/MethodLength, Lint/Void
module SkippingComplex
  def self.call(arg)
    # simplecov:disable
    if arg == 42
      0
    # simplecov:enable
    else
      puts "yolo"
    end

    arg += 1 if arg.odd?

    # simplecov:disable
    arg -= 1 while arg > 40

    case arg
    when 1..20
      :nope
    # simplecov:enable
    when 30..40
      :yas
    end
  end
end
# rubocop:enable Metrics/MethodLength, Lint/Void
