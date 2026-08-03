require "yaml"

module Yozgat
  module Deploy
    module Compose
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

        compose_path = detect_compose_file!(repo_dir)
        Logs.write_line(log_path, "using compose file #{compose_relative(repo_dir, compose_path)}")
        Logs.write_line(log_path, "validating docker compose configuration")
        validate_compose!(compose_path, has_domains: false)
        Logs.write_line(log_path, "compose validation passed")

        DB::Deployments.update_status!(ctx.deployment_id, "starting")
        Logs.write_line(log_path, "starting containers from user compose file")

        unless Docker.compose_up(base, deploy_dir, compose_path, log_path, build: false)
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

      def self.detect_compose_file!(repo_dir : String) : String
        Dockerfile.detect_compose_file(repo_dir) ||
          raise "docker-compose.yml or docker-compose.yaml not found at repository root"
      end

      def self.validate_compose!(compose_path : String, has_domains : Bool) : Nil
        content = File.read(compose_path)
        doc = YAML.parse(content)

        services = doc["services"]?
        service_map = services.try(&.as_h)
        raise "compose file must define a top-level 'services' mapping" unless service_map && !service_map.empty?

        return unless has_domains

        raise "Custom domains require Traefik labels in compose (P13)"
      end

      private def self.compose_relative(repo_dir : String, compose_path : String) : String
        if compose_path.starts_with?(repo_dir)
          rest = compose_path[repo_dir.size..].lstrip('\\').lstrip('/')
          return rest unless rest.empty?
        end
        File.basename(compose_path)
      end
    end
  end
end
