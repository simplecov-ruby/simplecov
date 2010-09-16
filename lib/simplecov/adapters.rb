#
# Adaptars are glorified SimpleCov configuration procs that can be easily 
# loaded using SimpleCov.start :rails and defined using
#   SimpleCov.adapters.define :foo do
#     # SimpleCov configuration here, same as in  SimpleCov.configure
#   end
#
class SimpleCov::Adapters < Hash
  # 
  # Define a SimpleCov adapter:
  #   SimpleCov.adapters.define 'rails' do
  #     # Same as SimpleCov.configure do .. here
  #   end
  #
  def define(name, &blk)
    name = name.to_sym
    raise "SimpleCov Adapter '#{name}' is already defined" unless self[name].nil?
    self[name] = blk
  end
  
  #
  # Applies the adapter of given name on SimpleCov.configure
  #
  def load(name)
    name = name.to_sym
    raise "Could not find SimpleCov Adapter called '#{name}'" unless has_key?(name)
    SimpleCov.configure(&self[name])
  end
end

SimpleCov.adapters.define 'root_filter' do
  # Exclude all files outside of simplecov root
  add_filter do |src|
    !(src.filename =~ /^#{SimpleCov.root}/)
  end
end

SimpleCov.adapters.define 'rails' do
  add_filter '/test/'
  add_filter '/features/'
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/db/'
  add_filter '/autotest/'
  add_filter '/vendor/bundle/'
  
  add_group 'Controllers', 'app/controllers'
  add_group 'Models', 'app/models'
  add_group 'Helpers', 'app/helpers'
  add_group 'Libraries', 'lib'
  add_group 'Plugins', 'vendor/plugins'
end