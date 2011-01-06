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
end