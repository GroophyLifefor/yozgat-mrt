require "yaml"

module Yozgat
  module Deploy
    module Dockerfile
      COMPOSE_MISSING_WITH_DOMAINS = "Dockerfile detected, but no docker-compose.yml in the repo. " \
                                     "When domains are configured, commit a docker-compose.yml with Traefik labels at the repo root."

      def self.execute!(ctx : Context) : Nil
        project = DB::Projects.deploy_source(ctx.project_id)
        domains = DB::Domains.list_deploy(ctx.project_id, ctx.environment_id)
        domain_names = domains.map { |d| d[:domainName] }
        has_domains = !domains.empty?
        port_only = !has_domains

        Yozgat::Traefik.ensure_if_needed! if has_domains

        Yozgat::Deploy.prepare_dirs!(ctx)
        base = Yozgat::Config.base_dir
        env_dir = Paths.environment_dir(ctx.project_id, ctx.env_slug)
        deploy_dir = Paths.deployment_dir(ctx.project_id, ctx.env_slug, ctx.deployment_slug)
        repo_dir = Paths.repo_dir(ctx.project_id, ctx.env_slug, ctx.deployment_slug)
        log_path = Paths.deploy_log_path(ctx.project_id, ctx.env_slug, ctx.deployment_slug)

        old_deploy_dir = Current.read_deployment_dir(env_dir)

        DB::Deployments.update_project_status!(ctx.project_id, "deploying")
        DB::Deployments.update_status!(ctx.deployment_id, "cloning")
        Logs.write_line(log_path, "cloning repository")

        Git.clone_and_checkout(
          project[:repoUrl],
          project[:authUsername],
          project[:authToken],
          repo_dir,
          ctx.commit_hash,
        )

        unless dockerfile_exists?(repo_dir)
          raise "Dockerfile not found at repository root"
        end

        user_compose = detect_compose_file(repo_dir)
        compose_path = if path = user_compose
                         Logs.write_line(log_path, "using compose file #{compose_relative(repo_dir, path)}")
                         Logs.write_line(log_path, "validating docker compose configuration")
                         validate_compose!(path, has_domains: has_domains, domain_names: domain_names)
                         Logs.write_line(log_path, "compose validation passed")
                         path
                      else
                        if has_domains
                          raise COMPOSE_MISSING_WITH_DOMAINS
                        end
                        generated = File.join(deploy_dir, "docker-compose.yml")
                        Logs.write_line(log_path, "no compose file in repo; generating docker-compose.yml")
                        container_port = detect_expose_port(repo_dir)
                        if container_port
                          Logs.write_line(log_path, "detected EXPOSE port #{container_port} from Dockerfile")
                        else
                          Logs.write_line(log_path, "no EXPOSE port found in Dockerfile; using default container port 8080")
                        end
                        File.write(generated, generate_auto_compose(ctx, repo_dir))
                        generated
                      end

        env_file_path = File.join(deploy_dir, ".env")
        has_env_vars = EnvVars.write_file!(ctx.project_id, ctx.environment_id, env_file_path)
        if has_env_vars
          Logs.write_line(log_path, "wrote environment file")
          if user_compose && !EnvVars.compose_references_dotenv?(compose_path)
            Logs.write_line(log_path, "warning: environment variables were written to .env but compose does not reference env_file: .env")
          end
        end

        if port_only && old_deploy_dir && old_deploy_dir != deploy_dir
          Logs.write_line(log_path, "port-only redeploy: stopping previous deployment before start")
          stop_previous!(ctx, old_deploy_dir, log_path)
        end

        DB::Deployments.update_status!(ctx.deployment_id, "building")
        Logs.write_line(log_path, "building and starting containers")

        unless Docker.compose_up(base, deploy_dir, compose_path, log_path, build: true, use_env_file: has_env_vars)
          Docker.compose_down(base, deploy_dir, compose_path, use_env_file: has_env_vars)
          raise "docker compose up failed"
        end

        unless Docker.wait_for_compose_services(base, deploy_dir, compose_path, use_env_file: has_env_vars)
          Docker.compose_down(base, deploy_dir, compose_path, use_env_file: has_env_vars)
          raise "Your app did not start within 60 seconds. Check the app logs below."
        end

        DB::Deployments.update_status!(ctx.deployment_id, "running")
        DB::Deployments.update_project_status!(ctx.project_id, "running")
        Logs.write_line(log_path, "deployment running")

        Current.update(env_dir, ctx.deployment_slug)
        Logs.write_line(log_path, "updated current pointer")

        if !has_domains && user_compose
          if host_port = Compose.detect_host_port(compose_path)
            if host_port != Yozgat::DB::Environments.fetch_host_port(ctx.project_id, ctx.environment_id)
              Yozgat::DB::Deployments.sync_host_port!(ctx.project_id, ctx.environment_id, ctx.deployment_id, host_port)
              Logs.write_line(log_path, "host port set to #{host_port} from compose ports")
            end
          end
        end

        if has_domains && old_deploy_dir && old_deploy_dir != deploy_dir
          Logs.write_line(log_path, "stopping previous deployment")
          stop_previous!(ctx, old_deploy_dir, log_path)
        end

        Logs.write_line(log_path, "deployment completed successfully")
      end

      def self.dockerfile_exists?(repo_dir : String) : Bool
        File.file?(File.join(repo_dir, "Dockerfile"))
      end

      def self.detect_compose_file(repo_dir : String) : String?
        yml = File.join(repo_dir, "docker-compose.yml")
        return yml if File.file?(yml)

        yaml = File.join(repo_dir, "docker-compose.yaml")
        return yaml if File.file?(yaml)

        nil
      end

      def self.validate_compose!(compose_path : String, has_domains : Bool, domain_names : Array(String) = [] of String) : Nil
        content = File.read(compose_path)
        doc = YAML.parse(content)

        services = doc["services"]?
        service_map = services.try(&.as_h)
        raise "compose file must define a top-level 'services' mapping" unless service_map && !service_map.empty?

        has_build = service_map.values.any? { |service| service["build"]? }
        unless has_build
          raise "compose file must define at least one service with a 'build' section for Dockerfile projects"
        end

        if has_domains
          ComposeValidate.validate_traefik!(compose_path, domain_names)
        else
          has_ports = service_map.values.any? do |service|
            ports = service["ports"]?
            ports ? !ports_empty?(ports) : false
          end
          raise "compose file must define at least one service with a 'ports' mapping when no domains are configured" unless has_ports
        end
      end

      def self.detect_expose_port(repo_dir : String) : Int64?
        path = File.join(repo_dir, "Dockerfile")
        return nil unless File.file?(path)

        File.each_line(path) do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.starts_with?('#')
          if match = stripped.match(/^EXPOSE\s+(\d+)/i)
            return match[1].to_i64?
          end
        end
        nil
      end

      def self.generate_auto_compose(ctx : Context, repo_dir : String) : String
        cname = Yozgat::Deploy.container_name(ctx.project_id, ctx.env_slug, ctx.deployment_slug)
        host_port = ctx.assigned_port || 8080
        container_port = detect_expose_port(repo_dir) || 8080

        "services:\n" \
          "  app:\n" \
          "    build:\n" \
          "      context: ./repo\n" \
          "      dockerfile: Dockerfile\n" \
          "    container_name: #{cname}\n" \
          "    restart: unless-stopped\n" \
          "    ports:\n" \
          "      - \"#{host_port}:#{container_port}\"\n"
      end

      private def self.compose_relative(repo_dir : String, compose_path : String) : String
        if compose_path.starts_with?(repo_dir)
          rest = compose_path[repo_dir.size..].lstrip('\\').lstrip('/')
          return rest unless rest.empty?
        end
        File.basename(compose_path)
      end

      private def self.ports_empty?(ports : YAML::Any) : Bool
        case ports.raw
        when Array then ports.as_a.empty?
        when Hash  then ports.as_h.empty?
        when Nil   then true
        else            false
        end
      end

      private def self.stop_previous!(ctx : Context, old_deploy_dir : String, log_path : String) : Nil
        compose = find_compose_in_deploy_dir(old_deploy_dir)
        return unless compose && File.exists?(compose)

        Docker.compose_down(Yozgat::Config.base_dir, old_deploy_dir, compose)
        slug = File.basename(old_deploy_dir)
        DB::Deployments.stop_by_slug!(ctx.project_id, ctx.environment_id, slug)
        Logs.write_line(log_path, "previous deployment stopped")
      end

      private def self.find_compose_in_deploy_dir(deploy_dir : String) : String?
        detect_compose_file(File.join(deploy_dir, "repo")) ||
          (path = File.join(deploy_dir, "docker-compose.yml"); File.file?(path) ? path : nil) ||
          (path = File.join(deploy_dir, "docker-compose.yaml"); File.file?(path) ? path : nil)
      end
    end
  end
end
