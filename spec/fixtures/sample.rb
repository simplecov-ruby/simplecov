# Foo class
class Foo
  def initialize
    @foo = "baz"
  end

  def bar
    @foo
  end

  # simplecov:disable
  def skipped
    @foo * 2
  end
  # simplecov:enable
end
