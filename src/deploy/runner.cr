module Yozgat
  module Deploy
    # Shared deploy orchestration (P7). Type-specific work is delegated in P8+.
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
      execute_stub!(ctx)
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

    private def self.execute_stub!(ctx : Context) : Nil
      prepare_dirs!(ctx)

      DB::Deployments.update_project_status!(ctx.project_id, "deploying")
      DB::Deployments.update_status!(ctx.deployment_id, "cloning")
      Logs.append(ctx, "cloning repository (stub)")

      DB::Deployments.update_status!(ctx.deployment_id, "starting")
      Logs.append(ctx, "starting deployment (stub)")

      DB::Deployments.update_status!(ctx.deployment_id, "running")
      DB::Deployments.update_project_status!(ctx.project_id, "running")
      Logs.append(ctx, "deployment running")

      env_dir = Paths.environment_dir(ctx.project_id, ctx.env_slug)
      Current.update(env_dir, ctx.deployment_slug)
      Logs.append(ctx, "updated current pointer")
      Logs.append(ctx, "deployment completed successfully")
    end
  end
end
