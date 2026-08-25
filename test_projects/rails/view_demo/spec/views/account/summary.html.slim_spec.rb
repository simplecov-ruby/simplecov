require "rails_helper"

RSpec.describe "account/summary" do
  # An account in good standing with recent orders: the past-due warning
  # and the no-orders empty state stay missed, and the order loop runs
  # three times.
  it "shows the profile beside its recent orders" do
    assign(:account, Account.new(name: "Ada", plan: "Pro", orders: ["#1001", "#1002", "#1003"]))

    render template: "account/summary"

    expect(rendered).to include("Ada")
    expect(rendered).to include("#1003")
  end
end
