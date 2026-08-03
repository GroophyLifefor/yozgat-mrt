require "file_utils"

module Yozgat
  module Deploy
    module Static
      alias DomainInput = NamedTuple(domainName: String, port: Int64)

      def self.execute!(ctx : Context) : Nil
        project = DB::Projects.deploy_source(ctx.project_id)
        domains = DB::Domains.list_deploy(ctx.project_id, ctx.environment_id)
        port_only = domains.empty?

        Yozgat::Traefik.ensure_if_needed! unless port_only

        Yozgat::Deploy.prepare_dirs!(ctx)
        base = Yozgat::Config.base_dir
        env_dir = Paths.environment_dir(ctx.project_id, ctx.env_slug)
        deploy_dir = Paths.deployment_dir(ctx.project_id, ctx.env_slug, ctx.deployment_slug)
        repo_dir = Paths.repo_dir(ctx.project_id, ctx.env_slug, ctx.deployment_slug)
        compose_path = File.join(deploy_dir, "docker-compose.yml")
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

        DB::Deployments.update_status!(ctx.deployment_id, "starting")
        Logs.write_line(log_path, "generating docker compose file")

        if port_only
          Logs.write_line(log_path, "no domains configured; exposing on host port #{ctx.assigned_port}")
        else
          Logs.write_line(log_path, "domains configured; routing via Traefik")
        end

        compose_yaml = generate_compose(
          project_id: ctx.project_id,
          env_slug: ctx.env_slug,
          deployment_slug: ctx.deployment_slug,
          repo_dir: repo_dir,
          domains: domains,
          host_port: ctx.assigned_port,
          router_name: Yozgat::Deploy.router_name(ctx.project_id, ctx.environment_id),
        )
        File.write(compose_path, compose_yaml)

        if port_only && old_deploy_dir && old_deploy_dir != deploy_dir
          Logs.write_line(log_path, "port-only redeploy: stopping previous deployment before start")
          stop_previous!(ctx, old_deploy_dir, log_path)
        end

        Logs.write_line(log_path, "starting containers")
        unless Docker.compose_up(base, deploy_dir, compose_path, log_path)
          Docker.compose_down(base, deploy_dir, compose_path)
          raise "docker compose up failed"
        end

        container = Yozgat::Deploy.container_name(ctx.project_id, ctx.env_slug, ctx.deployment_slug)
        unless Docker.wait_for_container_running(base, container)
          Docker.compose_down(base, deploy_dir, compose_path)
          raise "Your app did not start within 60 seconds. Check the app logs below."
        end

        DB::Deployments.update_status!(ctx.deployment_id, "running")
        DB::Deployments.update_project_status!(ctx.project_id, "running")
        Logs.write_line(log_path, "deployment running")

        Current.update(env_dir, ctx.deployment_slug)
        Logs.write_line(log_path, "updated current pointer")

        if !port_only && old_deploy_dir && old_deploy_dir != deploy_dir
          Logs.write_line(log_path, "stopping previous deployment")
          stop_previous!(ctx, old_deploy_dir, log_path)
        end

        Logs.write_line(log_path, "deployment completed successfully")
      end

      def self.generate_compose(
        project_id : Int64,
        env_slug : String,
        deployment_slug : String,
        repo_dir : String,
        domains : Array(DomainInput),
        host_port : Int64?,
        router_name : String,
      ) : String
        repo_mount = File.expand_path(repo_dir).gsub('\\', '/')
        cname = Yozgat::Deploy.container_name(project_id, env_slug, deployment_slug)

        if domains.empty?
          port = host_port || 8080
          return "services:\n" \
            "  website:\n" \
            "    image: joseluisq/static-web-server:2-alpine\n" \
            "    container_name: #{cname}\n" \
            "    restart: unless-stopped\n" \
            "    ports:\n" \
            "      - \"#{port}:80\"\n" \
            "    environment:\n" \
            "      - SERVER_ROOT=/var/public\n" \
            "    volumes:\n" \
            "      - #{repo_mount}:/var/public:ro\n"
        end

        host_rules = domains.map { |d| "Host(`#{d[:domainName]}`)" }.join(" || ")
        service_port = domains.first[:port]

        "services:\n" \
          "  website:\n" \
          "    image: joseluisq/static-web-server:2-alpine\n" \
          "    container_name: #{cname}\n" \
          "    restart: unless-stopped\n" \
          "    environment:\n" \
          "      - SERVER_ROOT=/var/public\n" \
          "    volumes:\n" \
          "      - #{repo_mount}:/var/public:ro\n" \
          "    labels:\n" \
          "      - \"traefik.enable=true\"\n" \
          "      - \"traefik.docker.network=traefik_net\"\n" \
          "      - \"traefik.http.routers.#{router_name}.rule=#{host_rules}\"\n" \
          "      - \"traefik.http.routers.#{router_name}.entrypoints=websecure\"\n" \
          "      - \"traefik.http.routers.#{router_name}.tls.certresolver=letsencrypt\"\n" \
          "      - \"traefik.http.services.#{router_name}.loadbalancer.server.port=#{service_port}\"\n" \
          "    networks:\n" \
          "      - traefik_net\n\n" \
          "networks:\n" \
          "  traefik_net:\n" \
          "    external: true\n"
      end

      private def self.stop_previous!(ctx : Context, old_deploy_dir : String, log_path : String) : Nil
        compose = File.join(old_deploy_dir, "docker-compose.yml")
        return unless File.exists?(compose)

        Docker.compose_down(Yozgat::Config.base_dir, old_deploy_dir, compose)
        slug = File.basename(old_deploy_dir)
        DB::Deployments.stop_by_slug!(ctx.project_id, ctx.environment_id, slug)
        Logs.write_line(log_path, "previous deployment stopped")
      end
    end
  end
end
