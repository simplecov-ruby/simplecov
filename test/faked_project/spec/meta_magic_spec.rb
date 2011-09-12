require 'spec_helper'

describe FakedProject do
  it "should have added a class method to FakedProject" do
    FakedProject.a_class_method.should == "this is a mixed-in class method"
  end

  its(:an_instance_method) { should == "this is a mixed-in instance method" }
  its(:dynamic) { should == "A dynamically defined instance method" }
end
