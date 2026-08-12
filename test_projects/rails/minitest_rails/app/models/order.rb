# frozen_string_literal: true

class Order
  def subtotal(quantity:, unit_price:)
    quantity * unit_price
  end
end
