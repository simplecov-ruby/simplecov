# frozen_string_literal: true

# Executed under production coverage. The two modes make different runs
# execute different branches, so the union-merge across separate
# processes is observable in the shared store.
class Workload
  def self.run(mode)
    if mode == "even"
      even_path
    else
      odd_path
    end
  end

  def self.even_path
    2 + 2
  end

  def self.odd_path
    3 + 3
  end
end
