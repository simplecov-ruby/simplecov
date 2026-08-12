# frozen_string_literal: true

require "test_helper"

class ReceiptTest < ActiveSupport::TestCase
  test "labels an order receipt" do
    wait_for_other_worker("receipt")

    assert_equal "Receipt #42", Receipt.new.label(42)
  end
end
