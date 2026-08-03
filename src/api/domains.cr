module Yozgat
  module API
    module Domains
      SUPPORTED_TYPES = {"static", "dockerfile", "dockercompose"}

      def self.list(env)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        return env.status(400).json({error: "invalid project or environment id"}) unless project_id && env_id

        return env.status(404).json({error: "environment not found"}) unless Yozgat::DB::Deployments.environment_belongs?(project_id, env_id)

        env.status(200).json({domains: Yozgat::DB::Domains.list(project_id, env_id)})
      end

      def self.verify(env, body : VerifyDomainBody)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        return env.status(400).json({error: "invalid project or environment id"}) unless project_id && env_id

        domain_name = body.domainName.strip.downcase
        return env.status(400).json({error: "invalid domain name"}) unless Yozgat::DB::Domains.domain_name_ok?(domain_name)

        expected = ensure_public_ip!(env)
        return unless expected

        return env.status(404).json({error: "environment not found"}) unless Yozgat::DB::Deployments.environment_belongs?(project_id, env_id)

        found_ips = Yozgat::DNS.verify_a_record(domain_name, expected)
        env.status(200).json({expectedIp: expected, foundIps: found_ips})
      rescue ex
        env.status(400).json({error: ex.message})
      end

      def self.create(env, body : CreateDomainBody)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        return env.status(400).json({error: "invalid project or environment id"}) unless project_id && env_id

        domain_name = body.domainName.strip.downcase
        return env.status(400).json({error: "invalid domain name"}) unless Yozgat::DB::Domains.domain_name_ok?(domain_name)

        expected = ensure_public_ip!(env)
        return unless expected

        return env.status(400).json({error: "domains are not supported for this project type"}) unless project_supports_domains?(project_id)

        port = (body.port || 80).to_i64
        unless port > 0 && port <= 65_535
          return env.status(400).json({error: "port must be between 1 and 65535"})
        end

        service_name = body.serviceName.try(&.strip)
        service_name = nil if service_name && service_name.empty?

        return env.status(404).json({error: "environment not found"}) unless Yozgat::DB::Deployments.environment_belongs?(project_id, env_id)

        unless Yozgat::Traefik.has_acme_email?
          begin
            Yozgat::Traefik.ensure_if_needed!
          rescue ex
            return env.status(503).json({error: ex.message})
          end
        end

        Yozgat::DNS.verify_a_record(domain_name, expected)

        row = Yozgat::DB::Domains.create(project_id, env_id, domain_name, service_name, port)
        env.status(201).json({domain: row})
      rescue ex : SQLite3::Exception
        if ex.message.try(&.includes?("UNIQUE"))
          env.status(409).json({error: "domain already exists for this environment"})
        else
          env.status(500).json({error: ex.message})
        end
      rescue ex
        env.status(400).json({error: ex.message})
      end

      def self.delete(env)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        domain_id = Projects.parse_id(env, "domain_id")
        return env.status(400).json({error: "invalid ids"}) unless project_id && env_id && domain_id

        if Yozgat::DB::Domains.delete(project_id, env_id, domain_id)
          env.status(200).json({ok: true})
        else
          env.status(404).json({error: "domain not found"})
        end
      end

      private def self.project_supports_domains?(project_id : Int64) : Bool
        ptype = Yozgat::DB::Projects.fetch_project_type(project_id)
        !ptype.nil? && SUPPORTED_TYPES.includes?(ptype)
      end

      private def self.ensure_public_ip!(env) : String?
        ip = Yozgat::Config.public_ip
        unless ip
          env.status(503).json({error: "YOZGAT_PUBLIC_IP is not configured on the server"})
          return nil
        end

        begin
          Yozgat::DNS.parse_expected_ipv4(ip)
        rescue
          env.status(503).json({error: "YOZGAT_PUBLIC_IP is not a valid IPv4 address"})
          nil
        end
      end
    end
  end
end

Ata.object CreateDomainBody do
  string :domainName, min: 1
  string :serviceName, optional: true
  int :port, optional: true
end

Ata.object VerifyDomainBody do
  string :domainName, min: 1
end

Ata.object DomainItem do
  int :id
  int :projectId
  int :environmentId
  string :domainName, min: 1
  string :serviceName, optional: true
  int :port
  string :createdAt, min: 1
end

Ata.object DomainListResponse do
  array :domains, of: DomainItem
end

Ata.object DomainResponse do
  object :domain, of: DomainItem
end

Ata.object VerifyDomainResponse do
  string :expectedIp, min: 1
  array :foundIps, of: :string
end

api :get, "/projects/:id/environments/:env_id/domains",
  summary: "List domains for an environment",
  tags: ["domains"],
  security: ["bearer_auth"],
  responses: {200 => DomainListResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::Domains.list(env)
end

api :post, "/projects/:id/environments/:env_id/domains",
  body: CreateDomainBody,
  summary: "Add a custom domain",
  tags: ["domains"],
  security: ["bearer_auth"],
  responses: {201 => DomainResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody, 409 => ErrorBody, 503 => ErrorBody} do
  Yozgat::API::Domains.create(env, body)
end

api :delete, "/projects/:id/environments/:env_id/domains/:domain_id",
  summary: "Remove a domain",
  tags: ["domains"],
  security: ["bearer_auth"],
  responses: {200 => OkBody, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::Domains.delete(env)
end

api :post, "/projects/:id/environments/:env_id/domains/verify",
  body: VerifyDomainBody,
  summary: "Verify domain DNS A record",
  tags: ["domains"],
  security: ["bearer_auth"],
  responses: {200 => VerifyDomainResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody, 503 => ErrorBody} do
  Yozgat::API::Domains.verify(env, body)
end
