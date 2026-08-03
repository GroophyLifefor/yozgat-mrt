module Yozgat
  module DB
    module EnvVars
      alias Row = NamedTuple(
        id: Int64,
        projectId: Int64,
        environmentId: Int64,
        key: String,
        value: String,
        createdAt: String,
      )

      alias Pair = NamedTuple(key: String, value: String)

      def self.list(project_id : Int64, environment_id : Int64) : Array(Row)
        rows = [] of Row
        Yozgat::DB.database.query(
          "SELECT id, project_id, environment_id, key, value, created_at
           FROM environment_variables
           WHERE project_id = ?1 AND environment_id = ?2
           ORDER BY key ASC",
          project_id, environment_id,
        ) do |rs|
          rs.each { rows << read_row(rs) }
        end
        rows
      end

      def self.list_pairs(project_id : Int64, environment_id : Int64) : Array(Pair)
        list(project_id, environment_id).map { |r| {key: r[:key], value: r[:value]} }
      end

      def self.find(project_id : Int64, environment_id : Int64, var_id : Int64) : Row?
        Yozgat::DB.database.query_one?(
          "SELECT id, project_id, environment_id, key, value, created_at
           FROM environment_variables
           WHERE id = ?1 AND project_id = ?2 AND environment_id = ?3",
          var_id, project_id, environment_id,
        ) { |rs| read_row(rs) }
      end

      def self.upsert(project_id : Int64, environment_id : Int64, key : String, value : String) : Row
        Yozgat::DB.database.exec(
          "INSERT INTO environment_variables (project_id, environment_id, key, value)
           VALUES (?1, ?2, ?3, ?4)
           ON CONFLICT(project_id, environment_id, key)
           DO UPDATE SET value = excluded.value",
          project_id, environment_id, key, value,
        )
        id = Yozgat::DB.database.query_one(
          "SELECT id FROM environment_variables
           WHERE project_id = ?1 AND environment_id = ?2 AND key = ?3",
          project_id, environment_id, key,
          as: Int64,
        )
        find(project_id, environment_id, id).not_nil!
      end

      def self.update(project_id : Int64, environment_id : Int64, var_id : Int64, value : String) : Row?
        result = Yozgat::DB.database.exec(
          "UPDATE environment_variables SET value = ?1
           WHERE id = ?2 AND project_id = ?3 AND environment_id = ?4",
          value, var_id, project_id, environment_id,
        )
        return nil if result.rows_affected == 0
        find(project_id, environment_id, var_id)
      end

      def self.delete(project_id : Int64, environment_id : Int64, var_id : Int64) : Bool
        Yozgat::DB.database.exec(
          "DELETE FROM environment_variables
           WHERE id = ?1 AND project_id = ?2 AND environment_id = ?3",
          var_id, project_id, environment_id,
        ).rows_affected > 0
      end

      private def self.read_row(rs : ::DB::ResultSet) : Row
        {
          id:            rs.read(Int64),
          projectId:     rs.read(Int64),
          environmentId: rs.read(Int64),
          key:           rs.read(String),
          value:         rs.read(String),
          createdAt:     rs.read(String),
        }
      end
    end
  end
end
