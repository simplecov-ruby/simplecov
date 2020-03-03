require 'spec_helper'
require 'open3'
describe 'spawn' do
  it 'calls things' do
    stdout, exitstatus = Open3.capture2("ruby -r#{__dir__}/../.simplecov_spawn #{__dir__}/../lib/command")
    expect(stdout.chomp).to eq 'done'
  end
end
