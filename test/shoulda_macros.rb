module ShouldaMacros
  #
  # Simple block helper for running certain tests only on specific ruby versions.
  # The given strings will be regexp-matched against RUBY_VERSION
  #
  def on_ruby(*ruby_versions)
    context "On Ruby #{RUBY_VERSION}" do
      yield
    end if ruby_versions.any? {|v| RUBY_VERSION =~ /#{v}/ }
  end

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
