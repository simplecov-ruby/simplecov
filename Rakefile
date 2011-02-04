require 'bundler'
Bundler::GemHelper.install_tasks

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

task :default => :test

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

TestedRubyVersions = %w(1.9.2 1.8.7 1.8.6 jruby-1.6.0.RC1)

desc "Perorms bundle install on all rvm-tested ruby versions (#{TestedRubyVersions.join(', ')})"
task :"multitest:bundle" do
  system "rvm #{TestedRubyVersions.join(',')} exec bundle install"
end

desc "Runs tests using rvm for: #{TestedRubyVersions.join(', ')}"
task :multitest do
  results = {}
  
  TestedRubyVersions.each do |ruby_version|
    puts "Invoking rake test on #{ruby_version}", "="*40
    
    if ruby_version =~ /jruby/
      puts "JRuby in Ruby 1.9 mode", "="*40
      system "rvm #{ruby_version} exec 'ruby --1.9 -S rake test'"
      results["#{ruby_version}-1.9"] = $?.exitstatus == 0
      
      puts "JRuby in Ruby 1.8 mode", "="*40
      system "rvm #{ruby_version} rake test"
      results["#{ruby_version}-1.8"] = $?.exitstatus == 0
    else
      system "rvm #{ruby_version} rake test"
      results["#{ruby_version}"] = $?.exitstatus == 0
    end
    
  end
  
  puts "", "Summary", "="*18
  results.each do |ruby, success|
    puts "#{ruby.ljust(18)}: #{success ? 'Passed' : 'Failed'}"
  end
  
  exit 1 if results.any? {|rb, success| !success}
end

