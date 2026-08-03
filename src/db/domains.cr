module Yozgat
  module DB
    module Domains
      DOMAIN_ALLOWED = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"

      alias Row = NamedTuple(
        id: Int64,
        projectId: Int64,
        environmentId: Int64,
        domainName: String,
        serviceName: String?,
        port: Int64,
        createdAt: String,
      )

      alias DeployRow = NamedTuple(domainName: String, port: Int64)

      def self.domain_name_ok?(name : String) : Bool
        s = name.strip
        return false if s.empty? || s.size > 253
        return false if s.starts_with?('.') || s.ends_with?('.')

        s.chars.all? { |c| DOMAIN_ALLOWED.includes?(c) }
      end

      def self.list(project_id : Int64, environment_id : Int64) : Array(Row)
        rows = [] of Row
        Yozgat::DB.database.query(
          "SELECT id, project_id, environment_id, domain_name, service_name, port, created_at
           FROM domains WHERE project_id = ?1 AND environment_id = ?2 ORDER BY id",
          project_id, environment_id,
        ) do |rs|
          rs.each { rows << read_row(rs) }
        end
        rows
      end

      def self.list_deploy(project_id : Int64, environment_id : Int64) : Array(DeployRow)
        list(project_id, environment_id).map { |row| {domainName: row[:domainName], port: row[:port]} }
      end

      def self.find(project_id : Int64, environment_id : Int64, domain_id : Int64) : Row?
        Yozgat::DB.database.query_one?(
          "SELECT id, project_id, environment_id, domain_name, service_name, port, created_at
           FROM domains WHERE id = ?1 AND project_id = ?2 AND environment_id = ?3",
          domain_id, project_id, environment_id,
        ) { |rs| read_row(rs) }
      end

      def self.create(
        project_id : Int64,
        environment_id : Int64,
        domain_name : String,
        service_name : String?,
        port : Int64,
      ) : Row
        Yozgat::DB.database.exec(
          "INSERT INTO domains (project_id, environment_id, domain_name, service_name, port)
           VALUES (?1, ?2, ?3, ?4, ?5)",
          project_id, environment_id, domain_name, service_name, port,
        )
        id = Yozgat::DB.database.query_one("SELECT last_insert_rowid()", as: Int64)
        find(project_id, environment_id, id).not_nil!
      end

      def self.delete(project_id : Int64, environment_id : Int64, domain_id : Int64) : Bool
        result = Yozgat::DB.database.exec(
          "DELETE FROM domains WHERE id = ?1 AND project_id = ?2 AND environment_id = ?3",
          domain_id, project_id, environment_id,
        )
        result.rows_affected > 0
      end

      private def self.read_row(rs : ::DB::ResultSet) : Row
        {
          id:            rs.read(Int64),
          projectId:     rs.read(Int64),
          environmentId: rs.read(Int64),
          domainName:    rs.read(String),
          serviceName:   rs.read(String?),
          port:          rs.read(Int64),
          createdAt:     rs.read(String),
        }
      end
    end
  end
end
