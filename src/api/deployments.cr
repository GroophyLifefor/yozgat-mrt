module Yozgat
  module API
    module Deployments
      def self.create(env, body : CreateDeploymentBody)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        return env.status(400).json({error: "invalid project or environment id"}) unless project_id && env_id

        commit_hash = body.commitHash.strip
        return env.status(400).json({error: "invalid commit hash"}) unless DB::Deployments.commit_hash_ok?(commit_hash)

        begin
          ctx = Deploy.start(project_id, env_id, commit_hash)
        rescue ex : ArgumentError
          msg = ex.message || "invalid request"
          status = case msg
                   when "environment not found"     then 404
                   when "project not found"        then 404
                   when "unsupported project type"  then 400
                   when "invalid commit hash"       then 400
                   else                               400
                   end
          return env.status(status).json({error: msg})
        end

        deployment = DB::Deployments.find(project_id, env_id, ctx.deployment_id)
        return env.status(500).json({error: "deployment record missing"}) unless deployment

        env.status(200).json({deployment: deployment})
      rescue ex
        env.status(500).json({error: ex.message})
      end

      def self.logs(env, query : DeploymentLogsQuery)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        deployment_id = Projects.parse_id(env, "deployment_id")
        return env.status(400).json({error: "invalid ids"}) unless project_id && deployment_id

        tail = (query.tail || 100).clamp(1, 1000)
        logs = DB::Deployments.read_logs(project_id, deployment_id, tail)
        return env.status(404).json({error: "deployment not found"}) unless logs

        env.status(200).json({logs: logs})
      end
    end
  end
end

# ── Schemas ─────────────────────────────────────────────────────

Ata.object CreateDeploymentBody do
  string :commitHash, min: 7
end

Ata.object DeploymentItem do
  int :id
  int :projectId
  int :environmentId
  string :commitHash, min: 7
  string :status, min: 1
  string :deploymentSlug, optional: true
  int :assignedPort, optional: true
  string :imageTag, optional: true
  string :createdAt, min: 1
end

Ata.object DeploymentResponse do
  object :deployment, of: DeploymentItem
end

Ata.object DeploymentLogsQuery do
  int :tail, optional: true
end

Ata.object DeploymentLogsBody do
  string :status, min: 1
  string :deployLog
  string :containerLog
end

Ata.object DeploymentLogsResponse do
  object :logs, of: DeploymentLogsBody
end

# ── Routes ──────────────────────────────────────────────────────

api :post, "/projects/:id/environments/:env_id/deployments",
  body: CreateDeploymentBody,
  summary: "Trigger a deployment for an environment",
  tags: ["deployments"],
  security: ["bearer_auth"],
  responses: {200 => DeploymentResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::Deployments.create(env, body)
end

api :get, "/projects/:id/deployments/:deployment_id/logs",
  query: DeploymentLogsQuery,
  summary: "Read deployment log tail",
  tags: ["deployments"],
  security: ["bearer_auth"],
  responses: {200 => DeploymentLogsResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::Deployments.logs(env, query)
end
