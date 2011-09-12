#
# Adapters are glorified SimpleCov configuration procs that can be easily
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
