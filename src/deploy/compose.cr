require "yaml"

module Yozgat
  module Deploy
    module Compose
      def self.execute!(ctx : Context) : Nil
        project = DB::Projects.deploy_source(ctx.project_id)
        domains = DB::Domains.list_deploy(ctx.project_id, ctx.environment_id)
        domain_names = domains.map { |d| d[:domainName] }
        has_domains = !domains.empty?

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

        compose_path = detect_compose_file!(repo_dir)
        Logs.write_line(log_path, "using compose file #{compose_relative(repo_dir, compose_path)}")
        Logs.write_line(log_path, "validating docker compose configuration")
        validate_compose!(compose_path, has_domains: has_domains, domain_names: domain_names)
        Logs.write_line(log_path, "compose validation passed")

        env_file_path = File.join(deploy_dir, ".env")
        has_env_vars = EnvVars.write_file!(ctx.project_id, ctx.environment_id, env_file_path)
        Logs.write_line(log_path, "wrote environment file") if has_env_vars

        DB::Deployments.update_status!(ctx.deployment_id, "starting")
        Logs.write_line(log_path, "starting containers from user compose file")

        unless Docker.compose_up(base, deploy_dir, compose_path, log_path, build: false, use_env_file: has_env_vars)
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

        if has_domains && old_deploy_dir && old_deploy_dir != deploy_dir
          Logs.write_line(log_path, "stopping previous deployment")
          stop_previous!(ctx, old_deploy_dir, log_path)
        end

        Logs.write_line(log_path, "deployment completed successfully")
      end

      def self.detect_compose_file!(repo_dir : String) : String
        Dockerfile.detect_compose_file(repo_dir) ||
          raise "docker-compose.yml or docker-compose.yaml not found at repository root"
      end

      def self.validate_compose!(compose_path : String, has_domains : Bool, domain_names : Array(String) = [] of String) : Nil
        content = File.read(compose_path)
        doc = YAML.parse(content)

        services = doc["services"]?
        service_map = services.try(&.as_h)
        raise "compose file must define a top-level 'services' mapping" unless service_map && !service_map.empty?

        if has_domains
          ComposeValidate.validate_traefik!(compose_path, domain_names)
        end
      end

      private def self.compose_relative(repo_dir : String, compose_path : String) : String
        if compose_path.starts_with?(repo_dir)
          rest = compose_path[repo_dir.size..].lstrip('\\').lstrip('/')
          return rest unless rest.empty?
        end
        File.basename(compose_path)
      end

      private def self.stop_previous!(ctx : Context, old_deploy_dir : String, log_path : String) : Nil
        compose = Dockerfile.detect_compose_file(File.join(old_deploy_dir, "repo"))
        return unless compose && File.exists?(compose)

        Docker.compose_down(Yozgat::Config.base_dir, old_deploy_dir, compose)
        slug = File.basename(old_deploy_dir)
        DB::Deployments.stop_by_slug!(ctx.project_id, ctx.environment_id, slug)
        Logs.write_line(log_path, "previous deployment stopped")
      end
    end
  end
end
