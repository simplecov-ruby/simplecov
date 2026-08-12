# So much skipping
# simplecov:disable
class Foo
  def bar(arg)
    if arg == 42
      0
    else
      1
    end
  end
end
# simplecov:enable
