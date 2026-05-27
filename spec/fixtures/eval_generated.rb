class EvalHost
  def_delegators :receiver, :hello
  def initialize(receiver)
    receiver ? @receiver = receiver : nil
  end
  attr_reader :receiver
end
