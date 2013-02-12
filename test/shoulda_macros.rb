module ShouldaMacros
  def should_be(boolean_flag)
    should "be #{boolean_flag}" do
      assert_equal true, subject.send(boolean_flag)
    end
  end

  def should_not_be(boolean_flag)
    should "not be #{boolean_flag}" do
      assert_equal false, subject.send(boolean_flag)
    end
  end

  def should_have(attr_name, expectation)
    should "have #{attr_name} == #{expectation.inspect}" do
      assert_equal expectation, subject.send(attr_name)
    end
  end
end
