require "yaml"

module Yozgat
  module Deploy
    module Dockerfile
      def self.execute!(ctx : Context) : Nil
        project = DB::Projects.deploy_source(ctx.project_id)
        domains = DB::Domains.list(ctx.project_id, ctx.environment_id)

        unless domains.empty?
          raise "Custom domains require Traefik (P13); use port-only deploy for now"
        end

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
                         validate_compose!(path, has_domains: false)
                         Logs.write_line(log_path, "compose validation passed")
                         path
                       else
                         generated = File.join(deploy_dir, "docker-compose.yml")
                         Logs.write_line(log_path, "no compose file in repo; generating docker-compose.yml")
                         File.write(generated, generate_auto_compose(ctx))
                         generated
                       end

        if old_deploy_dir && old_deploy_dir != deploy_dir
          Logs.write_line(log_path, "port-only redeploy: stopping previous deployment before start")
          stop_previous!(ctx, old_deploy_dir, log_path)
        end

        DB::Deployments.update_status!(ctx.deployment_id, "building")
        Logs.write_line(log_path, "building and starting containers")

        unless Docker.compose_up(base, deploy_dir, compose_path, log_path, build: true)
          Docker.compose_down(base, deploy_dir, compose_path)
          raise "docker compose up failed"
        end

        unless Docker.wait_for_compose_services(base, deploy_dir, compose_path)
          Docker.compose_down(base, deploy_dir, compose_path)
          raise "Your app did not start within 60 seconds. Check the app logs below."
        end

        DB::Deployments.update_status!(ctx.deployment_id, "running")
        DB::Deployments.update_project_status!(ctx.project_id, "running")
        Logs.write_line(log_path, "deployment running")

        Current.update(env_dir, ctx.deployment_slug)
        Logs.write_line(log_path, "updated current pointer")
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

      def self.validate_compose!(compose_path : String, has_domains : Bool) : Nil
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
          raise "Custom domains require Traefik labels in compose (P13)"
        end

        has_ports = service_map.values.any? do |service|
          ports = service["ports"]?
          ports ? !ports_empty?(ports) : false
        end
        raise "compose file must define at least one service with a 'ports' mapping when no domains are configured" unless has_ports
      end

      def self.generate_auto_compose(ctx : Context) : String
        cname = Yozgat::Deploy.container_name(ctx.project_id, ctx.env_slug, ctx.deployment_slug)
        port = ctx.assigned_port || 8080

        "services:\n" \
          "  app:\n" \
          "    build:\n" \
          "      context: ./repo\n" \
          "      dockerfile: Dockerfile\n" \
          "    container_name: #{cname}\n" \
          "    restart: unless-stopped\n" \
          "    ports:\n" \
          "      - \"#{port}:8080\"\n"
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
