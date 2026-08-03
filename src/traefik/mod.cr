module Yozgat
  module Traefik
    COMPOSE_TEMPLATE = {{ read_file("traefik/docker-compose.yml") }}
    ENV_FILE = "traefik.env"
    COMPOSE_FILE = "docker-compose.yml"
    NETWORK_NAME = "traefik_net"

    def self.traefik_dir : String
      File.join(Yozgat::Config.base_dir, "traefik")
    end

    def self.has_acme_email? : Bool
      !read_acme_email.nil?
    end

    def self.ensure_if_needed! : Nil
      dir = ensure_layout!
      unless has_acme_email?
        admin_email = Yozgat::DB.first_admin_email
        raise "admin user email not found; complete setup first" unless admin_email
        write_acme_email!(dir, admin_email)
      end
      ensure_network!
      docker_compose_up!(dir)
    end

    def self.ensure_with_email!(email : String) : Nil
      dir = ensure_layout!
      write_acme_email!(dir, email)
      ensure_network!
      docker_compose_up!(dir)
    end

    private def self.read_acme_email : String?
      path = File.join(traefik_dir, ENV_FILE)
      return nil unless File.file?(path)

      File.read_lines(path).each do |line|
        trimmed = line.strip
        if (value = trimmed.match(/^ACME_EMAIL=(.+)$/))
          email = value[1].strip
          return email unless email.empty?
        end
      end
      nil
    end

    private def self.ensure_layout! : String
      dir = traefik_dir
      Dir.mkdir_p(dir)
      File.write(File.join(dir, COMPOSE_FILE), COMPOSE_TEMPLATE)

      acme_path = File.join(dir, "acme.json")
      unless File.exists?(acme_path)
        File.write(acme_path, "")
      end

      {% if flag?(:unix) %}
        File.chmod(acme_path, 0o600)
      {% end %}

      dir
    end

    private def self.write_acme_email!(dir : String, email : String) : Nil
      trimmed = email.strip
      raise "acme email is empty" if trimmed.empty?
      File.write(File.join(dir, ENV_FILE), "ACME_EMAIL=#{trimmed}\n")
    end

    private def self.ensure_network! : Nil
      base = Yozgat::Config.base_dir
      env = Yozgat::Deploy::Docker.docker_env(base)

      inspect_ok = Process.run(
        "docker",
        ["network", "inspect", NETWORK_NAME],
        env: env,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close,
      ).success?

      return if inspect_ok

      unless Process.run(
               "docker",
               ["network", "create", NETWORK_NAME],
               env: env,
               output: Process::Redirect::Close,
               error: Process::Redirect::Close,
             ).success?
        raise "could not create docker network #{NETWORK_NAME}"
      end
    end

    private def self.docker_compose_up!(dir : String) : Nil
      env_file = File.join(dir, ENV_FILE)
      raise "traefik env file missing; ACME email not configured" unless File.file?(env_file)

      base = Yozgat::Config.base_dir
      output = IO::Memory.new
      stderr = IO::Memory.new

      ok = Process.run(
        "docker",
        ["compose", "--env-file", ENV_FILE, "-f", COMPOSE_FILE, "up", "-d"],
        chdir: dir,
        env: Yozgat::Deploy::Docker.docker_env(base, dir),
        output: output,
        error: stderr,
      ).success?

      return if ok

      err = stderr.to_s.strip
      err = output.to_s.strip if err.empty?
      raise "traefik compose up failed: #{err}"
    end
  end
end
