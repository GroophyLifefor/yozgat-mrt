module Yozgat
  module Deploy
    module Logs
      def self.write_line(path : String, message : String) : Nil
        Dir.mkdir_p(File.dirname(path))
        File.open(path, "a") do |file|
          file.puts("#{Time.utc.to_rfc3339} #{message}")
        end
      end

      def self.append(ctx : Context, message : String) : Nil
        path = Paths.deploy_log_path(ctx.project_id, ctx.env_slug, ctx.deployment_slug)
        write_line(path, message)
      end
    end
  end
end
