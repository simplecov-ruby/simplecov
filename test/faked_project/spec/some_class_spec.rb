require 'spec_helper'

describe SomeClass do
  subject { SomeClass.new("foo") }

  its(:reverse) { should == 'oof' }
  it "should compare with 'foo'" do
    subject.compare_with('foo').should be_true
  end
end
