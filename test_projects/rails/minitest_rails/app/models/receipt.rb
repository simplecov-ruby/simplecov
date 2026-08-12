# frozen_string_literal: true

class Receipt
  def label(order_number)
    "Receipt ##{order_number}"
  end
end
