module SimpleCov
  VERSION = "0.9.2"
  def VERSION.to_a
    split(".").map { |part| part.to_i }
  end

  def VERSION.major
    to_a[0]
  end

  def VERSION.minor
    to_a[1]
  end

  def VERSION.patch
    to_a[2]
  end

  def VERSION.pre
    to_a[3]
  end
end
