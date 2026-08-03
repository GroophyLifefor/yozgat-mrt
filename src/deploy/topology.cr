require "json"
require "yaml"
require "time"

module Yozgat
  module Deploy
    module Topology
      alias ContainerRow = NamedTuple(
        id: String,
        name: String,
        status: String,
        health: String,
      )

      alias NodeRow = NamedTuple(
        id: String,
        kind: String,
        name: String,
        image: String?,
        status: String,
        health: String,
        cpuPercent: Float64?,
        memoryPercent: Float64?,
        memoryBytes: Int64?,
        ports: Array(String),
        replicas: Int32,
        deployedAt: String?,
        containers: Array(ContainerRow),
        tier: Int32,
      )

      alias EdgeRow = NamedTuple(
        from: String,
        to: String,
        kind: String,
      )

      DB_TIER = 4
      PROXY_TIER = 1
      FRONTEND_TIER = 2
      API_TIER = 3

      def self.build(project_id : Int64, env_id : Int64) : NamedTuple(
        nodes: Array(NodeRow),
        edges: Array(EdgeRow),
        deploymentSlug: String?,
        updatedAt: String,
      )?
        return nil unless DB::Deployments.environment_belongs?(project_id, env_id)

        env_slug = DB::Deployments.fetch_env_slug(project_id, env_id)
        return nil unless env_slug

        env_dir = Paths.environment_dir(project_id, env_slug)
        deploy_dir = Current.read_deployment_dir(env_dir)
        return {
          nodes:          [] of NodeRow,
          edges:          [] of EdgeRow,
          deploymentSlug: nil,
          updatedAt:      Time.utc.to_rfc3339,
        } unless deploy_dir && Dir.exists?(deploy_dir)

        compose_path = find_compose_path(deploy_dir)
        deployment_slug = File.basename(deploy_dir)
        deployed_at = deployment_created_at(project_id, env_id, deployment_slug)

        base = Yozgat::Config.base_dir
        return empty(deployment_slug, deployed_at) unless Docker.docker_available?

        compose_services = compose_path ? parse_compose(compose_path) : [] of ComposeService
        containers = compose_path ? compose_ps(base, deploy_dir, compose_path) : [] of RuntimeContainer
        stats = stats_for(base, containers.map(&.[:id]))

        traefik = inspect_traefik(base)
        nodes = [] of NodeRow
        edges = [] of EdgeRow

        nodes << internet_node
        service_ids = Set(String).new

        if traefik
          nodes << traefik_node(traefik, stats)
          service_ids << "service:traefik"
          edges << {from: "internet", to: "service:traefik", kind: "ingress"}
        end

        grouped = group_by_service(containers, compose_services)
        grouped.each do |service_name, group|
          svc = compose_services.find { |s| s[:name] == service_name }
          id = service_id(service_name)
          next if service_ids.includes?(id)

          node = build_service_node(id, service_name, svc, group, stats, deployed_at)
          nodes << node
          service_ids << id

          if traefik && svc && svc[:traefikEnabled]
            edges << {from: "service:traefik", to: id, kind: "proxy"}
          elsif !traefik && nodes.size == 2
            edges << {from: "internet", to: id, kind: "ingress"}
          end
        end

        compose_services.each do |svc|
          from_id = service_id(svc[:name])
          next unless service_ids.includes?(from_id)

          svc[:dependsOn].each do |dep|
            to_id = service_id(dep)
            next unless service_ids.includes?(to_id)
            next if edges.any? { |e| e[:from] == from_id && e[:to] == to_id }

            edges << {from: from_id, to: to_id, kind: "depends_on"}
          end
        end

        if traefik && !edges.any? { |e| e[:from] == "service:traefik" } && nodes.size > 2
          first_app = nodes.find { |n| n[:kind] == "service" && n[:id] != "service:traefik" }
          if first_app
            edges << {from: "service:traefik", to: first_app[:id], kind: "proxy"}
          end
        end

        if !traefik && edges.empty? && nodes.size > 1
          app = nodes.find { |n| n[:kind] == "service" }
          edges << {from: "internet", to: app[:id], kind: "ingress"} if app
        end

        nodes = assign_tiers(nodes, edges)

        {
          nodes:          nodes,
          edges:          edges,
          deploymentSlug: deployment_slug,
          updatedAt:      Time.utc.to_rfc3339,
        }
      end

      private alias ComposeService = NamedTuple(
        name: String,
        image: String?,
        dependsOn: Array(String),
        traefikEnabled: Bool,
        tierHint: Int32,
      )

      private alias RuntimeContainer = NamedTuple(
        id: String,
        name: String,
        service: String,
        state: String,
        health: String,
        image: String,
        ports: Array(String),
      )

      private alias TraefikInfo = NamedTuple(
        id: String,
        name: String,
        state: String,
        health: String,
        image: String,
        ports: Array(String),
      )

      private alias StatInfo = NamedTuple(
        cpuPercent: Float64,
        memoryPercent: Float64,
        memoryBytes: Int64,
      )

      private def self.empty(slug : String?, deployed_at : String?) : NamedTuple(nodes: Array(NodeRow), edges: Array(EdgeRow), deploymentSlug: String?, updatedAt: String)
        {
          nodes:          [] of NodeRow,
          edges:          [] of EdgeRow,
          deploymentSlug: slug,
          updatedAt:      Time.utc.to_rfc3339,
        }
      end

      private def self.internet_node : NodeRow
        {
          id:             "internet",
          kind:           "external",
          name:           "Internet",
          image:          nil,
          status:         "external",
          health:         "healthy",
          cpuPercent:     nil,
          memoryPercent:  nil,
          memoryBytes:    nil,
          ports:          [] of String,
          replicas:       0,
          deployedAt:     nil,
          containers:     [] of ContainerRow,
          tier:           0,
        }
      end

      private def self.traefik_node(info : TraefikInfo, stats : Hash(String, StatInfo)) : NodeRow
        stat = stats[info[:id]]?
        {
          id:             "service:traefik",
          kind:           "service",
          name:           "traefik",
          image:          info[:image],
          status:         normalize_status(info[:state]),
          health:         info[:health],
          cpuPercent:     stat.try(&.[:cpuPercent]),
          memoryPercent:  stat.try(&.[:memoryPercent]),
          memoryBytes:    stat.try(&.[:memoryBytes]),
          ports:          info[:ports],
          replicas:       1,
          deployedAt:     nil,
          containers:     [{id: info[:id], name: info[:name], status: normalize_status(info[:state]), health: info[:health]}],
          tier:           PROXY_TIER,
        }
      end

      private def self.build_service_node(
        id : String,
        service_name : String,
        svc : ComposeService?,
        group : Array(RuntimeContainer),
        stats : Hash(String, StatInfo),
        deployed_at : String?,
      ) : NodeRow
        primary = group.first
        cpu_vals = [] of Float64
        mem_vals = [] of Float64
        mem_bytes = 0_i64

        group.each do |c|
          if s = stats[c[:id]]?
            cpu_vals << s[:cpuPercent]
            mem_vals << s[:memoryPercent]
            mem_bytes += s[:memoryBytes]
          end
        end

        avg = ->(vals : Array(Float64)) { vals.empty? ? nil : vals.sum / vals.size }

        containers = group.map do |c|
          {id: c[:id], name: c[:name], status: normalize_status(c[:state]), health: c[:health]}
        end

        status = aggregate_status(group)
        health = aggregate_health(group)

        {
          id:             id,
          kind:           "service",
          name:           service_name,
          image:          svc.try(&.[:image]) || primary[:image],
          status:         status,
          health:         health,
          cpuPercent:     avg.call(cpu_vals),
          memoryPercent:  avg.call(mem_vals),
          memoryBytes:    mem_bytes > 0 ? mem_bytes : nil,
          ports:          primary[:ports],
          replicas:       group.size.to_i32,
          deployedAt:     deployed_at,
          containers:     containers,
          tier:           svc.try(&.[:tierHint]) || tier_hint(service_name, svc.try(&.[:image]) || primary[:image]),
        }
      end

      private def self.service_id(name : String) : String
        "service:#{name}"
      end

      private def self.find_compose_path(deploy_dir : String) : String?
        Dockerfile.detect_compose_file(deploy_dir) ||
          Dockerfile.detect_compose_file(File.join(deploy_dir, "repo")) ||
          (path = File.join(deploy_dir, "docker-compose.yml"); File.file?(path) ? path : nil)
      end

      private def self.deployment_created_at(project_id : Int64, env_id : Int64, slug : String) : String?
        Yozgat::DB.database.query_one?(
          "SELECT created_at FROM deployments
           WHERE project_id = ?1 AND environment_id = ?2 AND deployment_slug = ?3
           ORDER BY id DESC LIMIT 1",
          project_id, env_id, slug,
          as: String,
        )
      end

      private def self.parse_compose(path : String) : Array(ComposeService)
        doc = YAML.parse(File.read(path))
        services = doc["services"]?.try(&.as_h)
        return [] of ComposeService unless services

        services.map do |name, cfg|
          name_s = name.as_s
          image = cfg["image"]?.try(&.as_s)
          depends = depends_on_list(cfg)
          labels = ComposeValidate.collect_labels(cfg["labels"]?)
          traefik = labels.any? { |l| l == "traefik.enable=true" }
          hint = tier_hint(name_s, image)

          {name: name_s, image: image, dependsOn: depends, traefikEnabled: traefik, tierHint: hint}
        end
      end

      private def self.depends_on_list(cfg : YAML::Any) : Array(String)
        dep = cfg["depends_on"]?
        return [] of String unless dep

        case raw = dep.raw
        when Array
          raw.compact_map(&.as_s?)
        when Hash
          raw.keys.compact_map(&.as_s?)
        else
          [] of String
        end
      end

      private def self.compose_ps(base : String, deploy_dir : String, compose_path : String) : Array(RuntimeContainer)
        rel = compose_relative(deploy_dir, compose_path)
        output = IO::Memory.new
        args = ["compose", "-f", rel, "ps", "-a", "--format", "json"]

        return [] of RuntimeContainer unless Process.run(
          "docker", args,
          chdir: deploy_dir,
          env: Docker.docker_env(base, deploy_dir),
          output: output,
          error: Process::Redirect::Close,
        ).success?

        rows = [] of RuntimeContainer
        output.to_s.each_line do |line|
          line = line.strip
          next if line.empty?

          begin
            obj = JSON.parse(line).as_h
            service = obj["Service"]?.try(&.as_s) || obj["Name"]?.try(&.as_s) || "unknown"
            name = obj["Name"]?.try(&.as_s) || service
            id = obj["ID"]?.try(&.as_s) || name
            state = obj["State"]?.try(&.as_s) || obj["Status"]?.try(&.as_s) || "unknown"
            health = obj["Health"]?.try(&.as_s) || health_from_state(state)
            image = obj["Image"]?.try(&.as_s) || ""
            ports = publishers_to_ports(obj["Publishers"]?)

            rows << {
              id: id, name: name, service: service, state: state,
              health: health, image: image, ports: ports,
            }
          rescue
            # skip malformed line
          end
        end
        rows
      end

      private def self.publishers_to_ports(value : JSON::Any?) : Array(String)
        return [] of String unless value

        ports = [] of String
        value.as_a.each do |pub|
          h = pub.as_h
          url = h["URL"]?.try(&.as_s)
          ports << url if url && !url.empty?
        end
        ports
      rescue
        [] of String
      end

      private def self.compose_relative(deploy_dir : String, compose_path : String) : String
        if compose_path.starts_with?(deploy_dir)
          rest = compose_path[deploy_dir.size..].lstrip('\\').lstrip('/')
          return rest unless rest.empty?
        end
        File.basename(compose_path)
      end

      private def self.inspect_traefik(base : String) : TraefikInfo?
        output = IO::Memory.new
        fmt = "{{.Id}}|{{.Name}}|{{.State.Status}}|{{.Config.Image}}|{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{(index $conf 0).HostPort}}:{{$p}} {{end}}{{end}}"
        return nil unless Process.run(
          "docker", ["inspect", "-f", fmt, "traefik"],
          env: Docker.docker_env(base),
          output: output,
          error: Process::Redirect::Close,
        ).success?

        parts = output.to_s.strip.split("|", 5)
        return nil if parts.size < 4

        ports = parts[4]?.try(&.split) || [] of String
        state = parts[2]
        {
          id: parts[0], name: parts[1].lstrip('/'), state: state,
          health: health_from_state(state), image: parts[3], ports: ports.reject(&.empty?),
        }
      rescue
        nil
      end

      private def self.stats_for(base : String, ids : Array(String)) : Hash(String, StatInfo)
        result = {} of String => StatInfo
        ids = ids.reject(&.empty?).uniq
        return result if ids.empty?

        output = IO::Memory.new
        return result unless Process.run(
          "docker", ["stats", "--no-stream", "--format", "{{json .}}"] + ids,
          env: Docker.docker_env(base),
          output: output,
          error: Process::Redirect::Close,
        ).success?

        output.to_s.each_line do |line|
          line = line.strip
          next if line.empty?

          begin
            obj = JSON.parse(line).as_h
            id = obj["ID"]?.try(&.as_s) || obj["Container"]?.try(&.as_s) || next
            cpu = parse_percent(obj["CPUPerc"]?.try(&.as_s))
            mem = parse_percent(obj["MemPerc"]?.try(&.as_s))
            mem_bytes = parse_mem_usage(obj["MemUsage"]?.try(&.as_s))
            result[id] = {cpuPercent: cpu, memoryPercent: mem, memoryBytes: mem_bytes}
          rescue
            # skip
          end
        end
        result
      end

      private def self.parse_percent(raw : String?) : Float64
        return 0.0 unless raw
        raw.gsub("%", "").to_f
      rescue
        0.0
      end

      private def self.parse_mem_usage(raw : String?) : Int64
        return 0_i64 unless raw
        left = raw.split("/").first?.try(&.strip)
        return 0_i64 unless left

        if left.ends_with?("GiB")
          (left.gsub("GiB", "").to_f * 1024 * 1024 * 1024).to_i64
        elsif left.ends_with?("MiB")
          (left.gsub("MiB", "").to_f * 1024 * 1024).to_i64
        elsif left.ends_with?("KiB")
          (left.gsub("KiB", "").to_f * 1024).to_i64
        else
          left.to_i64? || 0_i64
        end
      rescue
        0_i64
      end

      private def self.group_by_service(containers : Array(RuntimeContainer), compose_services : Array(ComposeService)) : Hash(String, Array(RuntimeContainer))
        grouped = Hash(String, Array(RuntimeContainer)).new { |h, k| h[k] = [] of RuntimeContainer }

        containers.each do |c|
          grouped[c[:service]] << c
        end

        compose_services.each do |svc|
          grouped[svc[:name]] ||= [] of RuntimeContainer
        end

        grouped
      end

      private def self.assign_tiers(nodes : Array(NodeRow), edges : Array(EdgeRow)) : Array(NodeRow)
        tiers = Hash(String, Int32).new
        nodes.each { |n| tiers[n[:id]] = n[:tier] }

        changed = true
        20.times do
          break unless changed
          changed = false
          edges.each do |edge|
            from_t = tiers[edge[:from]]?
            to_t = tiers[edge[:to]]?
            next unless from_t && to_t

            want = from_t + 1
            if to_t < want
              tiers[edge[:to]] = want
              changed = true
            end
          end
        end

        nodes.map do |n|
          tier = tiers[n[:id]]? || n[:tier]
          n[:tier] == tier ? n : n.merge(tier: tier)
        end
      end

      private def self.tier_hint(name : String, image : String?) : Int32
        n = "#{name} #{image}".downcase
        return PROXY_TIER if n.includes?("traefik") || n.includes?("nginx") || n.includes?("caddy")
        return DB_TIER if db_keyword?(n)
        return FRONTEND_TIER if n.includes?("front") || n.includes?("web") || n.includes?("static") || n.includes?("next")
        return API_TIER if n.includes?("api") || n.includes?("worker") || n.includes?("backend")
        API_TIER
      end

      private def self.db_keyword?(n : String) : Bool
        %w(postgres redis mysql mongo minio mariadb memcached elasticsearch rabbitmq).any? { |k| n.includes?(k) }
      end

      private def self.normalize_status(state : String) : String
        s = state.downcase
        return "running" if s.includes?("running") || s.includes?("up")
        return "stopped" if s.includes?("exited") || s.includes?("stopped")
        return "starting" if s.includes?("starting") || s.includes?("created")
        state
      end

      private def self.health_from_state(state : String) : String
        s = state.downcase
        return "healthy" if s.includes?("running") || s.includes?("up")
        return "warning" if s.includes?("starting")
        "error"
      end

      private def self.aggregate_status(group : Array(RuntimeContainer)) : String
        return "stopped" if group.empty?
        return "running" if group.any? { |c| normalize_status(c[:state]) == "running" }
        return "starting" if group.any? { |c| normalize_status(c[:state]) == "starting" }
        "stopped"
      end

      private def self.aggregate_health(group : Array(RuntimeContainer)) : String
        return "unknown" if group.empty?
        return "error" if group.any? { |c| c[:health] == "error" }
        return "warning" if group.any? { |c| c[:health] == "warning" }
        "healthy"
      end
    end
  end
end
