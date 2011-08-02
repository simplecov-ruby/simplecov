# See http://robots.thoughtbot.com/post/8087279685/use-capybara-on-any-html-fragment-or-page
def page
  in_current_dir do
    Capybara::Node::Simple.new(File.read('coverage/index.html'))
  end
end

Then /^I should see foo$/ do
  page.should have_content("All Files")
end