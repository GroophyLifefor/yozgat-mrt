module Yozgat
  module Deploy
    module Ports
      PORT_MIN = 8000
      PORT_MAX = 8999

      def self.valid?(port : Int64) : Bool
        PORT_MIN <= port <= PORT_MAX
      end

      def self.in_use?(port : Int64, exclude_environment_id : Int64) : Bool
        on_env = Yozgat::DB.database.query_one?(
          "SELECT 1 FROM environments WHERE host_port = ?1 AND id != ?2 LIMIT 1",
          port, exclude_environment_id,
          as: Int32,
        )
        return true if on_env

        Yozgat::DB.database.query_one?(
          "SELECT 1 FROM deployments
           WHERE assigned_port = ?1
             AND environment_id != ?2
             AND status IN ('pending', 'cloning', 'building', 'starting', 'running')
           LIMIT 1",
          port, exclude_environment_id,
          as: Int32,
        ) != nil
      end

      def self.allocate : Int64
        used = Set(Int64).new

        Yozgat::DB.database.query(
          "SELECT assigned_port FROM deployments
           WHERE assigned_port IS NOT NULL
             AND status IN ('pending', 'cloning', 'building', 'starting', 'running')",
        ) do |rs|
          used << rs.read(Int64)
        end

        Yozgat::DB.database.query(
          "SELECT host_port FROM environments WHERE host_port IS NOT NULL",
        ) do |rs|
          used << rs.read(Int64)
        end

        (PORT_MIN..PORT_MAX).each do |port|
          return port.to_i64 unless used.includes?(port.to_i64)
        end

        raise "No free ports left. Delete an old environment or contact your admin."
      end

      def self.resolve_for_environment(project_id : Int64, environment_id : Int64) : Int64
        env_port = Yozgat::DB.database.query_one?(
          "SELECT host_port FROM environments WHERE id = ?1 AND project_id = ?2",
          environment_id, project_id,
          as: Int64?,
        )
        return env_port if env_port

        last_port = Yozgat::DB.database.query_one?(
          "SELECT assigned_port FROM deployments
           WHERE project_id = ?1 AND environment_id = ?2 AND assigned_port IS NOT NULL
           ORDER BY id DESC LIMIT 1",
          project_id, environment_id,
          as: Int64?,
        )

        port = last_port || allocate

        Yozgat::DB.database.exec(
          "UPDATE environments SET host_port = ?1 WHERE id = ?2 AND project_id = ?3",
          port, environment_id, project_id,
        )

        port
      end
    end
  end
end
