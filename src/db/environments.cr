module Yozgat
  module DB
    module Environments
      SLUG_ALLOWED = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."

      alias Row = NamedTuple(
        id: Int64,
        projectId: Int64,
        name: String,
        slug: String,
        hostPort: Int64?,
        createdAt: String,
      )

      def self.slug_ok?(slug : String) : Bool
        !slug.empty? && slug.chars.all? { |c| SLUG_ALLOWED.includes?(c) }
      end

      def self.project_exists?(project_id : Int64) : Bool
        Yozgat::DB.database.query_one?(
          "SELECT 1 FROM projects WHERE id = ?1",
          project_id,
          as: Int32,
        ) != nil
      end

      def self.slug_taken?(project_id : Int64, slug : String) : Bool
        Yozgat::DB.database.query_one?(
          "SELECT 1 FROM environments WHERE project_id = ?1 AND slug = ?2",
          project_id, slug,
          as: Int32,
        ) != nil
      end

      def self.list(project_id : Int64) : Array(Row)
        rows = [] of Row
        Yozgat::DB.database.query(
          "SELECT id, project_id, name, slug, host_port, created_at
           FROM environments WHERE project_id = ?1 ORDER BY id DESC",
          project_id,
        ) do |rs|
          rs.each { rows << read_row(rs) }
        end
        rows
      end

      def self.find(project_id : Int64, env_id : Int64) : Row?
        Yozgat::DB.database.query_one?(
          "SELECT id, project_id, name, slug, host_port, created_at
           FROM environments WHERE id = ?1 AND project_id = ?2",
          env_id, project_id,
        ) { |rs| read_row(rs) }
      end

      def self.find_id_by_slug(project_id : Int64, slug : String) : Int64?
        return nil unless slug_ok?(slug)

        Yozgat::DB.database.query_one?(
          "SELECT id FROM environments WHERE project_id = ?1 AND slug = ?2",
          project_id, slug,
          as: Int64,
        )
      end

      def self.fetch_host_port(project_id : Int64, env_id : Int64) : Int64?
        Yozgat::DB.database.query_one?(
          "SELECT host_port FROM environments WHERE id = ?1 AND project_id = ?2",
          env_id, project_id,
          as: Int64?,
        )
      end

      def self.create(project_id : Int64, name : String, slug : String) : Row
        Yozgat::DB.database.exec(
          "INSERT INTO environments (project_id, name, slug) VALUES (?1, ?2, ?3)",
          project_id, name, slug,
        )
        id = Yozgat::DB.database.query_one("SELECT last_insert_rowid()", as: Int64)
        find(project_id, id).not_nil!
      end

      def self.update(project_id : Int64, env_id : Int64, name : String?, host_port : Int64?) : Row?
        return nil unless find(project_id, env_id)

        if name
          Yozgat::DB.database.exec(
            "UPDATE environments SET name = ?1 WHERE id = ?2 AND project_id = ?3",
            name, env_id, project_id,
          )
        end

        unless host_port.nil?
          Yozgat::DB.database.exec(
            "UPDATE environments SET host_port = ?1 WHERE id = ?2 AND project_id = ?3",
            host_port, env_id, project_id,
          )
        end

        find(project_id, env_id)
      end

      private def self.read_row(rs : ::DB::ResultSet) : Row
        {
          id:        rs.read(Int64),
          projectId: rs.read(Int64),
          name:      rs.read(String),
          slug:      rs.read(String),
          hostPort:  rs.read(Int64?),
          createdAt: rs.read(String),
        }
      end
    end
  end
end
