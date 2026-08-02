module Yozgat
  module API
    module Environments
      def self.list(env)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        return env.status(400).json({error: "invalid project id"}) unless project_id

        return env.status(404).json({error: "project not found"}) unless Yozgat::DB::Environments.project_exists?(project_id)

        env.status(200).json({environments: Yozgat::DB::Environments.list(project_id)})
      end

      def self.create(env, body : CreateEnvironmentBody)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        return env.status(400).json({error: "invalid project id"}) unless project_id

        name = body.name.strip
        return env.status(400).json({error: "name is required"}) if name.empty?

        slug = body.slug.strip
        unless Yozgat::DB::Environments.slug_ok?(slug)
          return env.status(400).json({error: "slug must be non-empty and contain only letters, digits, '.', '-', '_'"})
        end

        return env.status(404).json({error: "project not found"}) unless Yozgat::DB::Environments.project_exists?(project_id)
        return env.status(409).json({error: "environment slug already exists"}) if Yozgat::DB::Environments.slug_taken?(project_id, slug)

        row = Yozgat::DB::Environments.create(project_id, name, slug)
        env.status(201).json({environment: row})
      rescue ex
        env.status(500).json({error: ex.message})
      end

      def self.get(env)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        return env.status(400).json({error: "invalid project or environment id"}) unless project_id && env_id

        row = Yozgat::DB::Environments.find(project_id, env_id)
        return env.status(404).json({error: "environment not found"}) unless row

        env.status(200).json({environment: row})
      end

      def self.update(env, body : UpdateEnvironmentBody)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        return env.status(400).json({error: "invalid project or environment id"}) unless project_id && env_id

        name = body.name.try(&.strip)
        name = nil if name && name.empty?
        host_port = body.hostPort.try(&.to_i64)

        if name.nil? && host_port.nil?
          return env.status(400).json({error: "name or hostPort is required"})
        end

        return env.status(404).json({error: "environment not found"}) unless Yozgat::DB::Environments.find(project_id, env_id)

        if hp = host_port
          unless Yozgat::Deploy::Ports.valid?(hp)
            return env.status(400).json({error: "hostPort must be between #{Yozgat::Deploy::Ports::PORT_MIN} and #{Yozgat::Deploy::Ports::PORT_MAX}"})
          end
          if Yozgat::Deploy::Ports.in_use?(hp, env_id)
            return env.status(409).json({error: "host port is already in use"})
          end
        end

        row = Yozgat::DB::Environments.update(project_id, env_id, name, host_port)
        env.status(200).json({environment: row.not_nil!})
      rescue ex
        env.status(500).json({error: ex.message})
      end
    end
  end
end

# ── Schemas ─────────────────────────────────────────────────────

Ata.object CreateEnvironmentBody do
  string :name, min: 1
  string :slug, min: 1
end

Ata.object UpdateEnvironmentBody do
  string :name, min: 1, optional: true
  int :hostPort, optional: true
end

Ata.object EnvironmentItem do
  int :id
  int :projectId
  string :name, min: 1
  string :slug, min: 1
  int :hostPort, optional: true
  string :createdAt, min: 1
end

Ata.object EnvironmentListResponse do
  array :environments, of: EnvironmentItem
end

Ata.object EnvironmentResponse do
  object :environment, of: EnvironmentItem
end

# ── Routes ──────────────────────────────────────────────────────

api :get, "/projects/:id/environments",
  summary: "List environments for a project",
  tags: ["environments"],
  security: ["bearer_auth"],
  responses: {200 => EnvironmentListResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::Environments.list(env)
end

api :post, "/projects/:id/environments",
  body: CreateEnvironmentBody,
  summary: "Create an environment",
  tags: ["environments"],
  security: ["bearer_auth"],
  responses: {201 => EnvironmentResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody, 409 => ErrorBody} do
  Yozgat::API::Environments.create(env, body)
end

api :get, "/projects/:id/environments/:env_id",
  summary: "Get environment details",
  tags: ["environments"],
  security: ["bearer_auth"],
  responses: {200 => EnvironmentResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::Environments.get(env)
end

api :patch, "/projects/:id/environments/:env_id",
  body: UpdateEnvironmentBody,
  summary: "Update environment name and/or host port",
  tags: ["environments"],
  security: ["bearer_auth"],
  responses: {200 => EnvironmentResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody, 409 => ErrorBody} do
  Yozgat::API::Environments.update(env, body)
end
