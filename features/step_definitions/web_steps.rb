# frozen_string_literal: true

# Cucumber world helpers for scoping Capybara assertions to a selector.
module WithinHelpers
  def with_scope(locator, &)
    locator ? within(locator, &) : yield
  end
end
World(WithinHelpers)

When /^I open the coverage report$/ do
  visit "/"
  # New simplecov-html shows #wrapper via jQuery .show() after JS init;
  # wait for that or for old format where #content is always present
  page.has_css?("#content", visible: true, wait: 10)
end

When /^(?:|I )follow "([^"]*)"(?: within "([^"]*)")?$/ do |link, selector|
  with_scope(selector) do
    click_link(link)
  end
end

Then /^(?:|I )should see "([^"]*)"(?: within "([^"]*)")?$/ do |text, selector|
  with_scope(selector) do
    expect(page).to have_text(text)
  end
end

# the default in our settings is still to check unvisible content
# as well and until we change that these steps similar to "should (not)
# see" are necessary
Then "{string} should be visible" do |text|
  expect(page).to have_text(:visible, text)
end

Then "{string} should not be visible" do |text|
  expect(page).to have_no_text(:visible, text)
end
