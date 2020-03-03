class Subprocesses
  def run
    method_called_in_parent_process

    pid = Process.fork do
      method_called_by_subprocess
    end

    Process.wait(pid)

    true
  end

  def method_called_in_parent_process
    true
  end

  def method_called_by_subprocess
    true
  end
end
