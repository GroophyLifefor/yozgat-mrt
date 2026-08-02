module Yozgat
  # Subprocess helpers — never invoke a shell; args are passed verbatim.
  module Shell
    def self.run(
      command : String,
      args : Array(String) = [] of String,
      output : Process::IO = Process::Redirect::Close,
      error : Process::IO = Process::Redirect::Close,
      env : Hash(String, String)? = nil,
    ) : Process::Status
      Process.run(command, args, output: output, error: error, env: env)
    end
  end
end
