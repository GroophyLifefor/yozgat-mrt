require "yaml"

module Yozgat
  module Deploy
    module ComposeValidate
      TRAFFIC_ERROR = "No service is configured to receive traffic for the domain(s) on " \
                      "this environment. Add Traefik routing labels (or equivalent) to your " \
                      "docker-compose.yml in the repo, then redeploy."

      def self.validate_traefik!(compose_path : String, domain_names : Array(String)) : Nil
        content = File.read(compose_path)
        doc = YAML.parse(content)

        services = doc["services"]?
        service_map = services.try(&.as_h)
        raise "compose file must define a top-level 'services' mapping" unless service_map && !service_map.empty?

        traefik_enabled = false
        has_router = false
        has_traefik_net = false
        host_rules = Set(String).new

        service_map.each_value do |service|
          sm = service.as_h?
          next unless sm

          labels = collect_labels(sm["labels"]?)
          traefik_enabled = true if labels.any? { |l| l == "traefik.enable=true" }

          labels.each do |label|
            if label.starts_with?("traefik.http.routers.") && label.includes?(".rule=")
              has_router = true
              if (rule = label.split('=', limit: 2)[1]?)
                extract_hostnames(rule).each { |h| host_rules << h }
              end
            end
          end

          has_traefik_net = true if service_has_traefik_net?(sm)
        end

        unless traefik_enabled && has_router && has_traefik_net
          raise TRAFFIC_ERROR
        end

        configured = domain_names.map(&.downcase.strip).reject(&.empty?).to_set
        return if configured.empty?
        return unless (host_rules & configured).empty?

        found = host_rules.empty? ? "none found" : host_rules.join(", ")
        expected = configured.join(", ")
        raise "compose Traefik Host() rules (#{found}) do not match configured domains (#{expected}). Update docker-compose.yml and redeploy."
      end

      def self.collect_labels(value : YAML::Any?) : Array(String)
        return [] of String unless value

        case raw = value.raw
        when Array
          raw.compact_map do |item|
            item.as_s?.try(&.strip)
          end
        when Hash
          raw.compact_map do |k, v|
            key = k.as_s?.try(&.strip)
            val = v.as_s?.try(&.strip)
            key && val ? "#{key}=#{val}" : nil
          end
        else
          [] of String
        end
      end

      def self.service_has_traefik_net?(service_map : Hash(YAML::Any, YAML::Any)) : Bool
        networks = service_map["networks"]?
        return false unless networks

        case raw = networks.raw
        when Array
          raw.any? { |item| network_name_is_traefik?(item) }
        when Hash
          raw.keys.any? { |k| k.as_s?.try(&.strip) == "traefik_net" }
        else
          false
        end
      end

      def self.network_name_is_traefik?(value : YAML::Any) : Bool
        value.as_s?.try(&.strip) == "traefik_net"
      end

      def self.extract_hostnames(rule : String) : Array(String)
        hosts = [] of String
        rest = rule.downcase
        while (idx = rest.index("host(`"))
          rest = rest[(idx + 6)...]
          if (end_idx = rest.index('`'))
            host = rest[0...end_idx].strip
            hosts << host unless host.empty?
            rest = rest[(end_idx + 1)...]
          else
            break
          end
        end
        hosts
      end
    end
  end
end
