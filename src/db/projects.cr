require "file_utils"

module Yozgat
  module DB
    module Projects
      ALLOWED_TYPES         = {"static", "dockerfile", "dockercompose"}
      DEFAULT_STATUS        = "not_initialized"
      STATUS_REMOVING       = "removing"
      HAS_CREDS_SQL         = <<-SQL
        (auth_username IS NOT NULL AND TRIM(auth_username) != ''
         AND auth_token IS NOT NULL AND TRIM(auth_token) != '')
      SQL

      alias ListRow = NamedTuple(
        id: Int64,
        name: String,
        repoUrl: String,
        projectType: String,
        status: String,
        hasPrivateCredentials: Bool,
        createdAt: String,
      )

      alias DetailRow = NamedTuple(
        id: Int64,
        name: String,
        repoUrl: String,
        projectType: String,
        status: String,
        hasPrivateCredentials: Bool,
        webhookSecret: String,
        createdAt: String,
      )

      alias AuthCreds = NamedTuple(
        repoUrl: String,
        authUsername: String?,
        authToken: String?,
      )

      alias DeploySource = NamedTuple(
        repoUrl: String,
        authUsername: String?,
        authToken: String?,
        projectType: String,
      )

      def self.fetch_project_type(project_id : Int64) : String?
        Yozgat::DB.database.query_one?(
          "SELECT project_type FROM projects WHERE id = ?1",
          project_id,
          as: String,
        )
      end

      def self.list : Array(ListRow)
        rows = [] of ListRow
        Yozgat::DB.database.query(<<-SQL) do |rs|
          SELECT id, name, repo_url, project_type, status, created_at, #{HAS_CREDS_SQL}
          FROM projects
          ORDER BY id DESC
        SQL
          rows << read_list_row(rs)
        end
        rows
      end

      def self.find(id : Int64) : DetailRow?
        Yozgat::DB.database.query_one?(
          "SELECT id, name, repo_url, project_type, status, webhook_secret, created_at, #{HAS_CREDS_SQL} FROM projects WHERE id = ?1",
          id,
        ) { |rs| read_detail_row(rs) }
      end

      def self.auth_creds(id : Int64) : AuthCreds?
        Yozgat::DB.database.query_one?(
          "SELECT repo_url, auth_username, auth_token FROM projects WHERE id = ?1",
          id,
        ) do |rs|
          {
            repoUrl:      rs.read(String),
            authUsername: rs.read(String?),
            authToken:    rs.read(String?),
          }
        end
      end

      def self.deploy_source(id : Int64) : DeploySource
        Yozgat::DB.database.query_one(
          "SELECT repo_url, auth_username, auth_token, project_type FROM projects WHERE id = ?1",
          id,
        ) do |rs|
          {
            repoUrl:      rs.read(String),
            authUsername: rs.read(String?),
            authToken:    rs.read(String?),
            projectType:  rs.read(String),
          }
        end
      end

      def self.create(
        name : String,
        repo_url : String,
        project_type : String,
        auth_username : String?,
        auth_token : String?,
        webhook_secret : String,
      ) : ListRow
        Yozgat::DB.database.transaction do |tx|
          tx.connection.exec(
            "INSERT INTO projects (name, repo_url, auth_username, auth_token, webhook_secret, project_type, status)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            name, repo_url, auth_username, auth_token, webhook_secret, project_type, DEFAULT_STATUS,
          )
          id = tx.connection.query_one("SELECT last_insert_rowid()", as: Int64)
          tx.connection.exec(
            "INSERT INTO environments (project_id, name, slug) VALUES (?1, ?2, ?3)",
            id, "Production", "prod",
          )
          row = find_in_tx(tx, id).not_nil!
          detail_to_list(row)
        end.as(ListRow)
      end

      def self.delete(id : Int64) : Bool
        n = Yozgat::DB.database.exec("UPDATE projects SET status = ?1 WHERE id = ?2", STATUS_REMOVING, id).rows_affected
        return false if n == 0

        Yozgat::DB.database.exec("DELETE FROM projects WHERE id = ?1", id)
        project_dir = File.join(Yozgat::Config.base_dir, "projects", id.to_s)
        FileUtils.rm_rf(project_dir) if Dir.exists?(project_dir)
        true
      end

      def self.validate_project_type(raw : String) : String?
        t = raw.strip
        ALLOWED_TYPES.includes?(t) ? t : nil
      end

      def self.mint_webhook_secret : String
        Random::Secure.hex(32)
      end

      private def self.read_list_row(rs : ::DB::ResultSet) : ListRow
        {
          id:                      rs.read(Int64),
          name:                    rs.read(String),
          repoUrl:                 rs.read(String),
          projectType:             rs.read(String),
          status:                  rs.read(String),
          createdAt:               rs.read(String),
          hasPrivateCredentials:   rs.read(Int64) != 0,
        }
      end

      private def self.read_detail_row(rs : ::DB::ResultSet) : DetailRow
        {
          id:                      rs.read(Int64),
          name:                    rs.read(String),
          repoUrl:                 rs.read(String),
          projectType:             rs.read(String),
          status:                  rs.read(String),
          webhookSecret:           rs.read(String),
          createdAt:               rs.read(String),
          hasPrivateCredentials:   rs.read(Int64) != 0,
        }
      end

      private def self.find_in_tx(tx : ::DB::Transaction, id : Int64) : DetailRow?
        tx.connection.query_one?(
          "SELECT id, name, repo_url, project_type, status, webhook_secret, created_at, #{HAS_CREDS_SQL} FROM projects WHERE id = ?1",
          id,
        ) { |rs| read_detail_row(rs) }
      end

      private def self.detail_to_list(row : DetailRow) : ListRow
        {
          id:                    row[:id],
          name:                  row[:name],
          repoUrl:               row[:repoUrl],
          projectType:           row[:projectType],
          status:                row[:status],
          hasPrivateCredentials: row[:hasPrivateCredentials],
          createdAt:             row[:createdAt],
        }
      end
    end
  end
end
