require 'spec_helper'

describe FakedProject do
  it "should return proper foo" do
    FakedProject.foo.should == 'bar'
  end

  it "should test it's framework specific method" do
    FrameworkSpecific.rspec.should == "Only tested in RSpec"
  end
end
