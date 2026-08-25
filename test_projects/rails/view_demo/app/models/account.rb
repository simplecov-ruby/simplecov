# The profile the Slim summary template renders.
class Account
  attr_reader :name, :plan, :orders

  def initialize(name:, plan:, orders: [], past_due: false)
    @name = name
    @plan = plan
    @orders = orders
    @past_due = past_due
  end

  def past_due?
    @past_due
  end
end
