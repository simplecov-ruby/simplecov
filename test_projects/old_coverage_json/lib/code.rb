# frozen_string_literal: true

class Code
  def foo(arg)
    if arg == 42
      :foo
    else
      :bar
    end
  end
end
