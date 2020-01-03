# Adapted from https://github.com/colszowka/simplecov/pull/694#issuecomment-562097006
# rubocop:disable all
x = 1
x.eql?(4) ? "4" : x

puts x unless x.eql?(5)

unless x == 5
  puts "Ola.."
end

unless x != 5
  puts "Ola.."
end

unless x != 5
  puts "Ola.."
else
  puts "text"
end

puts x if x.eql?(5)
if x != 5
  puts "Ola.."
end

if x == 5
  puts "Ola.."
end

if x != 5
  puts "Ola.."
else
  puts "text"
end
x = 4
if x == 1
  puts "wow 1"
  puts "such excite!"
elsif x == 4
  4.times { puts "4!!!!"}
elsif x == 14
  puts "magic"

  puts "very"
else
  puts x
end

# rubocop:enable all
