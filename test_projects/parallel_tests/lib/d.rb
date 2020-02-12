# frozen_string_literal: true

class D
  def case(arg)
    case arg
    when 0...23
      :foo
    when 40..50
      :bar
    when Integer
      :baz
    else
      :nope
    end
  end
end
