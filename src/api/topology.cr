module Yozgat
  module API
    module Topology
      def self.get(env)
        return unless Projects.require_auth(env)
        project_id = Projects.parse_id(env)
        env_id = Projects.parse_id(env, "env_id")
        return env.status(400).json({error: "invalid project or environment id"}) unless project_id && env_id

        data = Yozgat::Deploy::Topology.build(project_id, env_id)
        return env.status(404).json({error: "environment not found"}) unless data

        env.status(200).json({
          topology: {
            nodes:          data[:nodes],
            edges:          data[:edges],
            deploymentSlug: data[:deploymentSlug],
            updatedAt:      data[:updatedAt],
          },
        })
      rescue ex
        env.status(500).json({error: ex.message})
      end

      # Global topology across all projects and environments, grouped
      # hierarchically so the dashboard map can render everything at once.
      def self.all(env)
        return unless Projects.require_auth(env)

        now = Time.utc.to_rfc3339
        projects = Yozgat::DB::Projects.list.map do |p|
          envs = Yozgat::DB::Environments.list(p[:id]).map do |e|
            data = Yozgat::Deploy::Topology.build(p[:id], e[:id])
            {
              id:             e[:id],
              slug:           e[:slug],
              name:           e[:name],
              hostPort:       e[:hostPort],
              deploymentSlug: data.try(&.[:deploymentSlug]),
              updatedAt:      data.try(&.[:updatedAt]) || now,
              nodes:          data ? data[:nodes] : [] of Yozgat::Deploy::Topology::NodeRow,
              edges:          data ? data[:edges] : [] of Yozgat::Deploy::Topology::EdgeRow,
            }
          end
          {
            id:           p[:id],
            name:         p[:name],
            projectType:  p[:projectType],
            status:       p[:status],
            environments: envs,
          }
        end

        env.status(200).json({topology: {projects: projects}})
      rescue ex
        env.status(500).json({error: ex.message})
      end
    end
  end
end

Ata.object TopologyContainerItem do
  string :id, min: 1
  string :name, min: 1
  string :status, min: 1
  string :health, min: 1
end

Ata.object TopologyNodeItem do
  string :id, min: 1
  string :kind, min: 1
  string :name, min: 1
  string :image, optional: true
  string :status, min: 1
  string :health, min: 1
  float :cpuPercent, optional: true
  float :memoryPercent, optional: true
  int :memoryBytes, optional: true
  array :ports, of: :string
  int :replicas
  string :deployedAt, optional: true
  array :containers, of: TopologyContainerItem
  int :tier
end

Ata.object TopologyEdgeItem do
  string :from, min: 1
  string :to, min: 1
  string :kind, min: 1
end

Ata.object TopologyBody do
  array :nodes, of: TopologyNodeItem
  array :edges, of: TopologyEdgeItem
  string :deploymentSlug, optional: true
  string :updatedAt, min: 1
end

Ata.object TopologyResponse do
  object :topology, of: TopologyBody
end

Ata.object TopologyEnvItem do
  int :id
  string :slug, min: 1
  string :name, min: 1
  int :hostPort, optional: true
  string :deploymentSlug, optional: true
  string :updatedAt, min: 1
  array :nodes, of: TopologyNodeItem
  array :edges, of: TopologyEdgeItem
end

Ata.object TopologyProjectItem do
  int :id
  string :name, min: 1
  string :projectType, min: 1
  string :status, min: 1
  array :environments, of: TopologyEnvItem
end

Ata.object TopologyProjectList do
  array :projects, of: TopologyProjectItem
end

Ata.object GlobalTopologyResponse do
  object :topology, of: TopologyProjectList
end

api :get, "/projects/:id/environments/:env_id/topology",
  summary: "Runtime service topology for map view",
  tags: ["topology"],
  security: ["bearer_auth"],
  responses: {200 => TopologyResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody, 500 => ErrorBody} do
  Yozgat::API::Topology.get(env)
end

api :get, "/topology",
  summary: "Global service topology across all projects and environments",
  tags: ["topology"],
  security: ["bearer_auth"],
  responses: {200 => GlobalTopologyResponse, 400 => ErrorBody, 401 => ErrorBody, 500 => ErrorBody} do
  Yozgat::API::Topology.all(env)
end
