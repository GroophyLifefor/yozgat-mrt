module Yozgat
  module API
    module Server
      def self.health(env)
        env.status(200).json({ok: true})
      end

      def self.info(env)
        claims = Yozgat::Auth.authenticated(env)
        return env.status(401).json({error: "unauthorized"}) unless claims

        base = Yozgat::Config.base_dir
        data = Yozgat::Config.data_dir
        db_path = Yozgat::Config.db_path

        env.status(200).json({
          version:  Yozgat::VERSION,
          publicIp: Yozgat::Config.public_ip,
          paths:    {
            baseDir: base,
            dataDir: data,
          },
          storage: storage_summary(db_path),
        })
      end

      private def self.storage_summary(db_path : String) : NamedTuple(dbBytes: Int64?)
        bytes = File.exists?(db_path) ? File.size(db_path).to_i64 : nil
        {dbBytes: bytes}
      end
    end
  end
end

Ata.object HealthBody do
  bool :ok
end

Ata.object StorageBody do
  int :dbBytes, optional: true
end

Ata.object PathsBody do
  string :baseDir, min: 1
  string :dataDir, min: 1
end

Ata.object ServerInfoBody do
  string :version, min: 1
  string :publicIp, optional: true
  object :paths, of: PathsBody
  object :storage, of: StorageBody
end

api :get, "/health",
  summary: "Liveness probe",
  tags: ["server"],
  responses: {200 => HealthBody} do
  Yozgat::API::Server.health(env)
end

api :get, "/server/info",
  summary: "Server version and runtime paths",
  tags: ["server"],
  security: ["bearer_auth"],
  responses: {200 => ServerInfoBody, 401 => ErrorBody} do
  Yozgat::API::Server.info(env)
end
