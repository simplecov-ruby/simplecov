# frozen_string_literal: true

require "test_helper"

class OrderTest < ActiveSupport::TestCase
  test "calculates a subtotal" do
    wait_for_other_worker("order")

    assert_equal 30, Order.new.subtotal(quantity: 3, unit_price: 10)
  end
end
