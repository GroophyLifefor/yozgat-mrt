module Yozgat
  module DB
    module Deployments
      ACTIVE_STATUSES = %w(pending cloning building starting running)

      alias Row = NamedTuple(
        id: Int64,
        projectId: Int64,
        environmentId: Int64,
        commitHash: String,
        status: String,
        deploymentSlug: String?,
        assignedPort: Int64?,
        imageTag: String?,
        createdAt: String,
      )

      def self.commit_hash_ok?(hash : String) : Bool
        !hash.empty? && hash.matches?(/^[0-9a-fA-F]{7,}$/)
      end

      def self.environment_belongs?(project_id : Int64, env_id : Int64) : Bool
        Yozgat::DB.database.query_one?(
          "SELECT 1 FROM environments WHERE id = ?1 AND project_id = ?2",
          env_id, project_id,
          as: Int32,
        ) != nil
      end

      def self.fetch_env_slug(project_id : Int64, env_id : Int64) : String?
        Yozgat::DB.database.query_one?(
          "SELECT slug FROM environments WHERE id = ?1 AND project_id = ?2",
          env_id, project_id,
          as: String,
        )
      end

      def self.fetch_project_type(project_id : Int64) : String?
        Yozgat::DB.database.query_one?(
          "SELECT project_type FROM projects WHERE id = ?1",
          project_id,
          as: String,
        )
      end

      def self.find(project_id : Int64, env_id : Int64, deployment_id : Int64) : Row?
        Yozgat::DB.database.query_one?(
          "SELECT id, project_id, environment_id, commit_hash, status, deployment_slug,
                  assigned_port, image_tag, created_at
           FROM deployments
           WHERE id = ?1 AND project_id = ?2 AND environment_id = ?3",
          deployment_id, project_id, env_id,
        ) { |rs| read_row(rs) }
      end

      def self.create_record!(project_id : Int64, env_id : Int64, commit_hash : String) : Yozgat::Deploy::Context
        raise ArgumentError.new("environment not found") unless environment_belongs?(project_id, env_id)

        ptype = fetch_project_type(project_id)
        raise ArgumentError.new("project not found") unless ptype
        unless Yozgat::DB::Projects::ALLOWED_TYPES.includes?(ptype)
          raise ArgumentError.new("unsupported project type")
        end

        hash = commit_hash.strip
        raise ArgumentError.new("invalid commit hash") unless commit_hash_ok?(hash)

        env_slug = fetch_env_slug(project_id, env_id)
        raise ArgumentError.new("environment not found") unless env_slug

        assigned_port = Yozgat::Deploy::Ports.resolve_for_environment(project_id, env_id)

        Yozgat::DB.database.exec(
          "INSERT INTO deployments (project_id, environment_id, commit_hash, status, assigned_port)
           VALUES (?1, ?2, ?3, 'pending', ?4)",
          project_id, env_id, hash, assigned_port,
        )
        deployment_id = Yozgat::DB.database.query_one("SELECT last_insert_rowid()", as: Int64)
        slug = Yozgat::Deploy::Slug.make(deployment_id)

        Yozgat::DB.database.exec(
          "UPDATE deployments SET deployment_slug = ?1 WHERE id = ?2",
          slug, deployment_id,
        )

        Yozgat::Deploy::Context.new(
          project_id: project_id,
          environment_id: env_id,
          deployment_id: deployment_id,
          deployment_slug: slug,
          commit_hash: hash,
          assigned_port: assigned_port,
          env_slug: env_slug,
        )
      end

      def self.update_status!(deployment_id : Int64, status : String) : Nil
        Yozgat::DB.database.exec(
          "UPDATE deployments SET status = ?1 WHERE id = ?2",
          status, deployment_id,
        )
      end

      def self.update_project_status!(project_id : Int64, status : String) : Nil
        Yozgat::DB.database.exec(
          "UPDATE projects SET status = ?1 WHERE id = ?2",
          status, project_id,
        )
      end

      def self.stop_by_slug!(project_id : Int64, environment_id : Int64, deployment_slug : String) : Nil
        Yozgat::DB.database.exec(
          "UPDATE deployments SET status = 'stopped'
           WHERE project_id = ?1 AND environment_id = ?2 AND deployment_slug = ?3
             AND status != 'failed'",
          project_id, environment_id, deployment_slug,
        )
      end

      def self.mark_failed!(deployment_id : Int64, project_id : Int64) : Nil
        update_status!(deployment_id, "failed")
        update_project_status!(project_id, "failed")
      end

      def self.peek_status(deployment_id : Int64) : String?
        Yozgat::DB.database.query_one?(
          "SELECT status FROM deployments WHERE id = ?1",
          deployment_id,
          as: String,
        )
      end

      private def self.read_row(rs : ::DB::ResultSet) : Row
        {
          id:             rs.read(Int64),
          projectId:      rs.read(Int64),
          environmentId:  rs.read(Int64),
          commitHash:     rs.read(String),
          status:         rs.read(String),
          deploymentSlug: rs.read(String?),
          assignedPort:   rs.read(Int64?),
          imageTag:       rs.read(String?),
          createdAt:      rs.read(String),
        }
      end
    end
  end
end
