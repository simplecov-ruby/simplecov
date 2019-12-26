class Inline
  def call(arg)
    String(arg == 42 ? :yes : :no)

    String(
      if arg.odd?
        :yes
      else
        :no
      end
    )
  end
end
