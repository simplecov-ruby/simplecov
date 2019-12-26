class Branches
  def call(arg)
    return if arg < 0

    arg == 42 ? :yes : :no

    if arg.odd?
      :yes
    else
      :no
    end
  end
end
