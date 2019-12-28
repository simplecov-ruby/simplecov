# yes rubocop you are right but I want to test nesting!
# rubocop:disable Metrics/BlockNesting
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
# rubocop:enable Metrics/BlockNesting
