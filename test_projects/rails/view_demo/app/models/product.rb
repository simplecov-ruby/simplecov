# A storefront product. Plain Ruby rather than ActiveRecord: the demo has
# no database, and the templates only read attributes.
class Product
  attr_reader :name, :price, :sale_price

  def initialize(name:, price:, sale_price: nil)
    @name = name
    @price = price
    @sale_price = sale_price
  end

  def on_sale?
    !sale_price.nil?
  end
end
