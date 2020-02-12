# frozen_string_literal: true

class A
  def foo
    :foo
  end

  def cond(arg)
    if arg
      :yes
    else
      :no
    end
  end
end
