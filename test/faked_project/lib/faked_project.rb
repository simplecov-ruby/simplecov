class FakedProject
  def self.foo
    "bar"
  end
end

require 'faked_project/some_class'
require 'faked_project/meta_magic'
require 'faked_project/framework_specific'

FakedProject.send :include, MetaMagic