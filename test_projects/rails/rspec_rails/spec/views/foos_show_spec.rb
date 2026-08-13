require "rails_helper"

RSpec.describe "foos/show", type: :view do
  it "renders the foo" do
    assign(:foo, Foo.new)
    assign(:admin, false)

    render template: "foos/show"

    expect(rendered).to include("bar")
  end
end
