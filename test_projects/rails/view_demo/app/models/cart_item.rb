# A line in the cart template's table.
class CartItem
  attr_reader :name, :quantity

  def initialize(name:, quantity:, gift: false)
    @name = name
    @quantity = quantity
    @gift = gift
  end

  def gift?
    @gift
  end
end
