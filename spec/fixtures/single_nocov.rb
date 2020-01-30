# :nocov:
module SingleNocov
  def self.call(arg)
    if arg.odd?
      :odd
    elsif arg == 30
      :mop
    elsif arg == 42
      :yay
    else
      :nay
    end
  end
end
