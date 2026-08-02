module Yozgat
  module DB
    # Applies versioned SQL migrations tracked in `_yozgat_migrations`.
    # SQL is embedded at compile time so release binaries stay self-contained.
    module Migrations
      struct Entry
        getter version : Int32
        getter name : String
        getter sql : String

        def initialize(@version, @name, @sql)
        end
      end

      {% begin %}
      ALL = [
        Entry.new(1, "001_users", {{ read_file("src/db/migrations/sql/001_users.sql") }}),
        Entry.new(2, "002_refresh_tokens", {{ read_file("src/db/migrations/sql/002_refresh_tokens.sql") }}),
        Entry.new(3, "003_projects", {{ read_file("src/db/migrations/sql/003_projects.sql") }}),
        Entry.new(4, "004_projects_status", {{ read_file("src/db/migrations/sql/004_projects_status.sql") }}),
        Entry.new(5, "005_environments", {{ read_file("src/db/migrations/sql/005_environments.sql") }}),
        Entry.new(6, "006_deployments", {{ read_file("src/db/migrations/sql/006_deployments.sql") }}),
        Entry.new(7, "007_domains", {{ read_file("src/db/migrations/sql/007_domains.sql") }}),
        Entry.new(8, "008_deployment_slug", {{ read_file("src/db/migrations/sql/008_deployment_slug.sql") }}),
        Entry.new(9, "009_assigned_port", {{ read_file("src/db/migrations/sql/009_assigned_port.sql") }}),
        Entry.new(10, "010_backfill_default_env", {{ read_file("src/db/migrations/sql/010_backfill_default_env.sql") }}),
        Entry.new(11, "011_environment_host_port", {{ read_file("src/db/migrations/sql/011_environment_host_port.sql") }}),
        Entry.new(12, "012_environment_variables", {{ read_file("src/db/migrations/sql/012_environment_variables.sql") }}),
      ] of Entry
      {% end %}

      def self.ensure_table!(db : ::DB::Database)
        db.exec <<-SQL
          CREATE TABLE IF NOT EXISTS _yozgat_migrations (
            version INTEGER PRIMARY KEY NOT NULL,
            name TEXT NOT NULL UNIQUE,
            applied_at TEXT NOT NULL DEFAULT (datetime('now'))
          );
        SQL
      end

      def self.current_version(db : ::DB::Database) : Int32
        db.query_one(
          "SELECT COALESCE(MAX(version), 0) FROM _yozgat_migrations",
          as: Int64,
        ).to_i32
      end

      def self.table_exists?(db : ::DB::Database, name : String) : Bool
        !db.query_one?(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          args: [name],
          as: Int64,
        ).nil?
      end

      # Pre-migration Crystal installs used PRAGMA user_version = 1 with only
      # `users`. Mark 001 as applied without re-running CREATE TABLE.
      def self.bootstrap_legacy!(db : ::DB::Database)
        return unless current_version(db) == 0
        return unless table_exists?(db, "users")

        db.exec(
          "INSERT INTO _yozgat_migrations (version, name) VALUES (?, ?)",
          args: [1, "001_users"],
        )
      end

      def self.apply_sql!(conn : ::DB::Connection, sql : String)
        sql.split(';', remove_empty: true).each do |statement|
          trimmed = statement.strip
          next if trimmed.empty?
          conn.exec(trimmed)
        end
      end

      def self.run!(db : ::DB::Database)
        ensure_table!(db)
        bootstrap_legacy!(db)

        current = current_version(db)

        ALL.each do |entry|
          next if entry.version <= current

          unless entry.version == current + 1
            raise "migration gap: database at version #{current}, expected next #{current + 1}, got #{entry.version} (#{entry.name})"
          end

          db.transaction do |tx|
            apply_sql!(tx.connection, entry.sql)
            tx.connection.exec(
              "INSERT INTO _yozgat_migrations (version, name) VALUES (?, ?)",
              args: [entry.version, entry.name],
            )
          end

          current = entry.version
        end

        db.exec("PRAGMA user_version = #{current}")
      end
    end
  end
end
