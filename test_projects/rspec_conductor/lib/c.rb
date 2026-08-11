# frozen_string_literal: true

class C
  def guard(arg)
    return if arg == 42

    :super
  end
end
