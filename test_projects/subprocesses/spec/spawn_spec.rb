require 'spec_helper'
require 'open3'
describe 'spawn' do
  it 'calls things' do
    Dir.chdir(File.expand_path('..', __dir__)) do
      stdout, exitstatus = Open3.capture2("ruby -r./.simplecov_spawn lib/command")
      expect(stdout.chomp).to eq 'done'
    end
  end
end
