module Yozgat
  module Deploy
    # Filesystem layout for deployments (see migration plan).
    module Paths
      def self.environment_dir(project_id : Int64, env_slug : String) : String
        File.join(base, "projects", project_id.to_s, "environments", env_slug)
      end

      def self.deployment_dir(project_id : Int64, env_slug : String, deployment_slug : String) : String
        File.join(environment_dir(project_id, env_slug), "deployments", deployment_slug)
      end

      def self.repo_dir(project_id : Int64, env_slug : String, deployment_slug : String) : String
        File.join(deployment_dir(project_id, env_slug, deployment_slug), "repo")
      end

      def self.deploy_log_path(project_id : Int64, env_slug : String, deployment_slug : String) : String
        File.join(environment_dir(project_id, env_slug), "logs", "#{deployment_slug}.log")
      end

      def self.current_pointer(project_id : Int64, env_slug : String) : String
        File.join(environment_dir(project_id, env_slug), "current")
      end

      private def self.base : String
        Yozgat::Config.base_dir
      end
    end

    # Creates yozgat-owned docker config/tmp dirs under base_dir.
    def self.ensure_runtime_dirs! : Nil
      base = Yozgat::Config.base_dir
      Dir.mkdir_p(File.join(base, ".docker"))
      Dir.mkdir_p(File.join(base, "tmp"))
    end
  end
end
