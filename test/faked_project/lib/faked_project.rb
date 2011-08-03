class FakedProject
  def self.foo
    "bar"
  end
end

require 'faked_project/some_class'
require 'faked_project/meta_magic'

FakedProject.send :include, MetaMagic