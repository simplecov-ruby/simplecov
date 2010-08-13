require 'rubygems'
require 'test/unit'
require 'shoulda'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'simple_cov'

class Test::Unit::TestCase
  def source_fixture(filename)
    File.expand_path(File.join(File.dirname(__FILE__), 'fixtures', filename))
  end
end
