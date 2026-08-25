require "rails_helper"

RSpec.describe "products/index" do
  # No promo message and a non-empty catalog, so the report shows the
  # promo banner and the empty state as missed lines with missed branch
  # markers on their `if`s. The price partial runs once per product, and
  # both of its arms are reached: one product is on sale, two are not.
  it "lists every product with its price" do
    assign(:products, [
      Product.new(name: "Espresso cup", price: "$14"),
      Product.new(name: "Pour-over kettle", price: "$59", sale_price: "$39"),
      Product.new(name: "Burr grinder", price: "$129")
    ])

    render template: "products/index"

    expect(rendered).to include("Espresso cup")
    expect(rendered).to include("$39")
    expect(rendered).to include("$129")
  end
end
