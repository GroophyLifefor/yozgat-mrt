module Yozgat
  module API
    module EnvVars
      def self.list(env)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        return env.status(400).json({error: "invalid project or environment id"}) unless project_id && env_id

        return env.status(404).json({error: "environment not found"}) unless Yozgat::DB::Deployments.environment_belongs?(project_id, env_id)

        env.status(200).json({envVars: Yozgat::DB::EnvVars.list(project_id, env_id)})
      end

      def self.create(env, body : UpsertEnvVarBody)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        return env.status(400).json({error: "invalid project or environment id"}) unless project_id && env_id

        key = body.key.strip
        return env.status(400).json({error: "key must match ^[A-Z_][A-Z0-9_]*$"}) unless Yozgat::Deploy::EnvVars.key_ok?(key)

        return env.status(404).json({error: "environment not found"}) unless Yozgat::DB::Deployments.environment_belongs?(project_id, env_id)

        row = Yozgat::DB::EnvVars.upsert(project_id, env_id, key, body.value)
        env.status(200).json({envVar: row})
      rescue ex
        env.status(500).json({error: ex.message})
      end

      def self.update(env, body : UpdateEnvVarBody)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        var_id = Projects.parse_id(env, "var_id")
        return env.status(400).json({error: "invalid ids"}) unless project_id && env_id && var_id

        row = Yozgat::DB::EnvVars.update(project_id, env_id, var_id, body.value)
        return env.status(404).json({error: "environment variable not found"}) unless row

        env.status(200).json({envVar: row})
      rescue ex
        env.status(500).json({error: ex.message})
      end

      def self.delete(env)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        var_id = Projects.parse_id(env, "var_id")
        return env.status(400).json({error: "invalid ids"}) unless project_id && env_id && var_id

        if Yozgat::DB::EnvVars.delete(project_id, env_id, var_id)
          env.status(200).json({ok: true})
        else
          env.status(404).json({error: "environment variable not found"})
        end
      end
    end
  end
end

Ata.object UpsertEnvVarBody do
  string :key, min: 1
  string :value
end

Ata.object UpdateEnvVarBody do
  string :value
end

Ata.object EnvVarItem do
  int :id
  int :projectId
  int :environmentId
  string :key, min: 1
  string :value
  string :createdAt, min: 1
end

Ata.object EnvVarListResponse do
  array :envVars, of: EnvVarItem
end

Ata.object EnvVarResponse do
  object :envVar, of: EnvVarItem
end

api :get, "/projects/:id/environments/:env_id/env-vars",
  summary: "List environment variables",
  tags: ["env-vars"],
  security: ["bearer_auth"],
  responses: {200 => EnvVarListResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::EnvVars.list(env)
end

api :post, "/projects/:id/environments/:env_id/env-vars",
  body: UpsertEnvVarBody,
  summary: "Create or update an environment variable",
  tags: ["env-vars"],
  security: ["bearer_auth"],
  responses: {200 => EnvVarResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::EnvVars.create(env, body)
end

api :patch, "/projects/:id/environments/:env_id/env-vars/:var_id",
  body: UpdateEnvVarBody,
  summary: "Update an environment variable value",
  tags: ["env-vars"],
  security: ["bearer_auth"],
  responses: {200 => EnvVarResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::EnvVars.update(env, body)
end

api :delete, "/projects/:id/environments/:env_id/env-vars/:var_id",
  summary: "Delete an environment variable",
  tags: ["env-vars"],
  security: ["bearer_auth"],
  responses: {200 => OkBody, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::EnvVars.delete(env)
end
