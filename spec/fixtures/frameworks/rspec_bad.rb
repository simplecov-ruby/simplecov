$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "..", "..", ".."))
require "lib/simplecov"
require "rspec"
SimpleCov.print_errors ENV["PRINT_ERRORS"] == "true" if ENV.key? "PRINT_ERRORS"
SimpleCov.start
RSpec.describe "exit status" do
  it "exits with a non-zero exit status when assertion fails" do
    expect(1).to eq(2)
  end
end
