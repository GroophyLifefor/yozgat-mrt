module Yozgat
  module Deploy
    module Docker
      def self.compose_up(
        base_dir : String,
        project_dir : String,
        compose_path : String,
        log_path : String,
        build : Bool = false,
        use_env_file : Bool = false,
      ) : Bool
        compose_arg = project_relative_path(project_dir, compose_path)
        args = ["compose"]
        args.concat(["--env-file", ".env"]) if use_env_file
        args.concat(["-f", compose_arg, "up", "-d"])
        args << "--build" if build

        output = IO::Memory.new
        stderr = IO::Memory.new
        ok = Process.run(
          "docker",
          args,
          chdir: project_dir,
          env: docker_env(base_dir, project_dir),
          output: output,
          error: stderr,
        ).success?

        if ok
          stdout = output.to_s
          Logs.write_line(log_path, "docker compose up:\n#{stdout}") unless stdout.empty?
          true
        else
          Logs.write_line(log_path, "docker compose up failed:\n#{output}\n#{stderr}")
          false
        end
      end

      def self.compose_down(
        base_dir : String,
        project_dir : String,
        compose_path : String,
        use_env_file : Bool = false,
      ) : Nil
        compose_arg = project_relative_path(project_dir, compose_path)
        args = ["compose"]
        args.concat(["--env-file", ".env"]) if use_env_file
        args.concat(["-f", compose_arg, "down"])

        Process.run(
          "docker",
          args,
          chdir: project_dir,
          env: docker_env(base_dir, project_dir),
          output: Process::Redirect::Close,
          error: Process::Redirect::Close,
        )
      end

      def self.wait_for_compose_services(
        base_dir : String,
        project_dir : String,
        compose_path : String,
        use_env_file : Bool = false,
      ) : Bool
        compose_arg = project_relative_path(project_dir, compose_path)

        30.times do
          output = IO::Memory.new
          args = ["compose"]
          args.concat(["--env-file", ".env"]) if use_env_file
          args.concat(["-f", compose_arg, "ps", "--status", "running", "--format", "json"])

          if Process.run(
               "docker",
               args,
               chdir: project_dir,
               env: docker_env(base_dir, project_dir),
               output: output,
               error: Process::Redirect::Close,
             ).success?
            return true if output.to_s.lines.any? { |line| !line.strip.empty? }
          end

          sleep 1.seconds
        end

        false
      end

      def self.wait_for_container_running(base_dir : String, name : String) : Bool
        30.times do
          output = IO::Memory.new
          if Process.run(
               "docker",
               ["inspect", "-f", "{{.State.Running}}", name],
               env: docker_env(base_dir),
               output: output,
               error: Process::Redirect::Close,
             ).success? && output.to_s.strip == "true"
            return true
          end
          sleep 1.seconds
        end
        false
      end

      def self.container_logs(base_dir : String, name : String, tail : Int32) : String
        return "" unless docker_available?

        output = IO::Memory.new
        stderr = IO::Memory.new
        tail_s = tail.clamp(1, 1000).to_s
        Process.run(
          "docker",
          ["logs", "--tail", tail_s, name],
          env: docker_env(base_dir),
          output: output,
          error: stderr,
        )
        out = output.to_s
        err = stderr.to_s
        out.empty? ? err : (err.empty? ? out : "#{out}\n#{err}")
      rescue
        ""
      end

      def self.docker_available? : Bool
        Process.run(
          "docker",
          ["version"],
          output: Process::Redirect::Close,
          error: Process::Redirect::Close,
        ).success?
      rescue
        false
      end

      private def self.docker_env(base_dir : String, project_dir : String? = nil) : Hash(String, String)
        Yozgat::Deploy.ensure_runtime_dirs!
        Dir.mkdir_p(File.join(project_dir, "tmp")) if project_dir
        ENV.to_h.merge({
          "HOME"          => abs_path(base_dir),
          "DOCKER_CONFIG" => abs_path(File.join(base_dir, ".docker")),
          "TMPDIR"        => abs_path(File.join(base_dir, "tmp")),
        })
      end

      private def self.abs_path(path : String) : String
        File.expand_path(path).gsub('\\', '/')
      end

      private def self.project_relative_path(project_dir : String, compose_path : String) : String
        if compose_path.starts_with?(project_dir)
          rest = compose_path[project_dir.size..].lstrip('\\').lstrip('/')
          return rest unless rest.empty?
        end
        File.basename(compose_path)
      end
    end
  end
end
