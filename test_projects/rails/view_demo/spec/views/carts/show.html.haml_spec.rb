require "rails_helper"

RSpec.describe "carts/show" do
  # A cart with items, one of them gift wrapped, and no coupon: the empty
  # state and the coupon note show up as missed, the gift branch as
  # covered.
  it "renders the cart table with a total" do
    assign(:items, [
      CartItem.new(name: "Espresso cup", quantity: 2),
      CartItem.new(name: "Gift card", quantity: 1, gift: true)
    ])
    assign(:total, "$64")

    render template: "carts/show"

    expect(rendered).to include("Gift wrapped")
    expect(rendered).to include("$64")
  end
end
