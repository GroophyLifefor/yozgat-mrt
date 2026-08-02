module Yozgat
  module Deploy
    module Current
      def self.update(env_dir : String, deployment_slug : String) : Nil
        pointer = File.join(env_dir, "current")
        File.delete(pointer) if File.exists?(pointer)

        {% if flag?(:unix) %}
          File.symlink(File.join("deployments", deployment_slug), pointer)
        {% else %}
          File.write(pointer, deployment_slug)
        {% end %}
      end

      def self.read_deployment_dir(env_dir : String) : String?
        pointer = File.join(env_dir, "current")
        return nil unless File.exists?(pointer)

        {% if flag?(:unix) %}
          target = File.readlink(pointer)
          return nil if target.empty?
          Path[target].absolute?(env_dir) ? target : File.join(env_dir, target)
        {% else %}
          slug = File.read(pointer).strip
          return nil if slug.empty?
          File.join(env_dir, "deployments", slug)
        {% end %}
      end
    end
  end
end
