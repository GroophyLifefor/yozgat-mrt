require "sqlite3"

module Yozgat
  module DB
    # Ordered, gap-free schema migrations. `PRAGMA user_version` tracks the
    # highest applied migration index (1-based).
    MIGRATIONS = [
      <<-SQL,
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'admin',
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      SQL
    ] of String

    @@database : ::DB::Database?

    def self.database : ::DB::Database
      @@database.not_nil!
    end

    # Opens the SQLite file (creating the directory as needed) and applies
    # pending migrations. WAL + busy_timeout + NORMAL synchronous — same
    # settings as the Rust backend.
    def self.open! : ::DB::Database
      Dir.mkdir_p(Yozgat::Config.data_dir)
      path = Yozgat::Config.db_path
      db = ::DB.open(db_uri(path))
      migrate(db)
      @@database = db
    end

    # The sqlite3 driver rebuilds the filename from `uri.hostname + uri.path`,
    # so a Windows drive letter ("C:") must stay out of the authority part or
    # it is dropped. Encoding the colon keeps it in the filename.
    private def self.db_uri(path : String) : String
      p = path.gsub('\\', '/').sub(/^([A-Za-z]):/, "\\1%3A")
      "sqlite3://#{p}?busy_timeout=5000&foreign_keys=on&journal_mode=wal&synchronous=normal"
    end

    def self.migrate(db : ::DB::Database)
      current = db.query_one("PRAGMA user_version", as: Int64)
      MIGRATIONS.each_with_index do |sql, i|
        version = i + 1
        next if version <= current
        db.transaction do |tx|
          tx.connection.exec(sql)
          tx.connection.exec("PRAGMA user_version = #{version}")
        end
      end
    end
  end
end
