module UnevenDisables
  def self.call(arg)
    # simplecov:disable
    if arg.odd?
      :odd
    elsif arg == 30
      :mop
    # simplecov:enable
    elsif arg == 42
      :yay
    # simplecov:disable
    else
      :nay
    end
  end
end
