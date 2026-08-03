require "yaml"

module Yozgat
  module Deploy
    module EnvVars
      KEY_PATTERN = /^[A-Z_][A-Z0-9_]*$/

      def self.key_ok?(key : String) : Bool
        !key.empty? && key.matches?(KEY_PATTERN)
      end

      def self.write_file!(project_id : Int64, environment_id : Int64, output_path : String) : Bool
        pairs = DB::EnvVars.list_pairs(project_id, environment_id)
        if pairs.empty?
          File.delete(output_path) if File.exists?(output_path)
          return false
        end

        lines = pairs.map do |pair|
          raise "invalid environment variable key in database: #{pair[:key]}" unless key_ok?(pair[:key])
          "#{pair[:key]}=#{escape_value(pair[:value])}"
        end

        Dir.mkdir_p(File.dirname(output_path))
        File.write(output_path, lines.join("\n") + "\n")
        true
      end

      def self.compose_references_dotenv?(compose_path : String) : Bool
        doc = YAML.parse(File.read(compose_path))
        services = doc["services"]?.try(&.as_h)
        return false unless services

        services.values.any? do |service|
          env_file = service["env_file"]?
          next false unless env_file
          case raw = env_file.raw
          when String
            raw.strip == ".env"
          when Array
            raw.any? { |item| item.as_s?.try(&.strip) == ".env" }
          else
            false
          end
        end
      rescue
        false
      end

      private def self.escape_value(value : String) : String
        return "" if value.empty?
        needs_quotes = value.chars.any? { |c| c.whitespace? || c == '"' || c == '#' || c == '$' }
        return value unless needs_quotes

        "\"#{value.gsub("\\", "\\\\").gsub("\"", "\\\"")}\""
      end
    end
  end
end
