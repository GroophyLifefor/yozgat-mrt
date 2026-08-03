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

api :get, "/projects/:id/environments/:env_id/topology",
  summary: "Runtime service topology for map view",
  tags: ["topology"],
  security: ["bearer_auth"],
  responses: {200 => TopologyResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody, 500 => ErrorBody} do
  Yozgat::API::Topology.get(env)
end
