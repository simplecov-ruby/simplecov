# frozen_string_literal: true
# Ruby can't even execute this file but it might be added
# via track_files or similar means and we still don't wanna crash!

class NoDeclare
  MSG = "おはよう"

  def ??
    "tada!"
  end
end
