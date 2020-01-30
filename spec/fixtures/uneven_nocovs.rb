module UnevenNocov
  def self.call(arg)
    # :nocov:
    if arg.odd?
      :odd
    elsif arg == 30
      :mop
    # :nocov:
    elsif arg == 42
      :yay
    # :nocov:
    else
      :nay
    end
  end
end
