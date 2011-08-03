require 'spec_helper'

describe FakedProject do
  it "should return proper foo" do
    FakedProject.foo.should == 'bar'
  end
end