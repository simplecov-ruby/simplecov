# frozen_string_literal: true

class Branches
  def call(arg)
    return if arg.negative?

    _val = (arg == 42 ? :yes : :no)

    if arg.odd?
      :yes
    else
      :no
    end
  end
end
