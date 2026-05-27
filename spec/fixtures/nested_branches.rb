module NestedBranches
  def self.call(arg)
    if arg.even?
      if arg == 42
        arg -= 1 while arg > 40
        :ok
      end
    else
      :nope
    end
  end
end
