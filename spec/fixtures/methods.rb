class A
  def method1
    puts "hello from method1"
    method2
  end

private

  def method2
    puts "hello from method2"
  end

  def method3
    puts "hello from method3"
  end
end

A.new.method1
