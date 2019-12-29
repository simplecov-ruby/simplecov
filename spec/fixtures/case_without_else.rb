module Case
  def self.call(arg)
    case arg
    when 0...23
      :foo
    when 40..50
      :bar
    when Integer
      :baz
    end
  end
end
