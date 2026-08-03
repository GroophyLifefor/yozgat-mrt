module Yozgat
  module Deploy
    def self.start(project_id : Int64, environment_id : Int64, commit_hash : String) : Context
      ctx = DB::Deployments.create_record!(project_id, environment_id, commit_hash)
      spawn(ctx)
      ctx
    end

    def self.spawn(ctx : Context) : Nil
      ::spawn do
        run(ctx)
      rescue ex
        DB::Deployments.mark_failed!(ctx.deployment_id, ctx.project_id)
        Logs.append(ctx, "ERROR: #{ex.message}")
      end
    end

    def self.run(ctx : Context) : Nil
      case DB::Projects.fetch_project_type(ctx.project_id)
      when "static"
        Static.execute!(ctx)
      when "dockerfile"
        Dockerfile.execute!(ctx)
      else
        raise "unsupported project type for deployment"
      end
    end

    def self.prepare_dirs!(ctx : Context) : String
      env_dir = Paths.environment_dir(ctx.project_id, ctx.env_slug)
      deploy_dir = Paths.deployment_dir(ctx.project_id, ctx.env_slug, ctx.deployment_slug)
      repo_dir = Paths.repo_dir(ctx.project_id, ctx.env_slug, ctx.deployment_slug)
      log_path = Paths.deploy_log_path(ctx.project_id, ctx.env_slug, ctx.deployment_slug)

      Dir.mkdir_p(File.join(env_dir, "logs"))
      Dir.mkdir_p(deploy_dir)
      Dir.mkdir_p(repo_dir)

      Logs.write_line(log_path, "deployment started")
      log_path
    end

    def self.container_name(project_id : Int64, env_slug : String, deployment_slug : String) : String
      "yozgat-#{project_id}-#{env_slug}-#{deployment_slug}"
    end

    def self.router_name(project_id : Int64, environment_id : Int64) : String
      "proj#{project_id}env#{environment_id}"
    end
  end
end
