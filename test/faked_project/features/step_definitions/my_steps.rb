Given /^I want to keep stuff simple$/ do
  1.should == 1
end

When /^I write my cukes for the fake project$/ do
  1.should == 1
end

Then /^I make all neccessary tests in a single step$/ do
  FakedProject.foo.should == 'bar'

  FrameworkSpecific.cucumber.should == "Only tested in Cucumber"

  FakedProject.a_class_method.should == "this is a mixed-in class method"

  FakedProject.new.an_instance_method.should == "this is a mixed-in instance method"
  FakedProject.new.dynamic.should == "A dynamically defined instance method"

  something = SomeClass.new("foo")
  something.reverse.should == 'oof'
  something.compare_with('foo').should be_true
end

