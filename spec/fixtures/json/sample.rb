# Foo class
class Foo
  def initialize
    @foo = "bar"
    @bar = "foo"
  end

  def bar
    @foo
  end

  def foo(param)
    if param
      @bar
    else
      @foo
    end
  end

  # :nocov:
  def skipped
    @foo * 2
  end
  # :nocov:
end
