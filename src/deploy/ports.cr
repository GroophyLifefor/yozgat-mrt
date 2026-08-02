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
    end
  end
end
