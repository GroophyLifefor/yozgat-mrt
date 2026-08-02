require "sqlite3"
require "./migrations"

module Yozgat
  module DB
    @@database : ::DB::Database?

    def self.database : ::DB::Database
      @@database.not_nil!
    end

    # Opens the SQLite file (creating the directory as needed) and applies
    # pending migrations. WAL + busy_timeout + NORMAL synchronous.
    def self.open! : ::DB::Database
      Dir.mkdir_p(Yozgat::Config.data_dir)
      path = Yozgat::Config.db_path
      db = ::DB.open(db_uri(path))
      Migrations.run!(db)
      @@database = db
    end

    # The sqlite3 driver rebuilds the filename from `uri.hostname + uri.path`,
    # so a Windows drive letter ("C:") must stay out of the authority part or
    # it is dropped. Encoding the colon keeps it in the filename.
    private def self.db_uri(path : String) : String
      p = path.gsub('\\', '/').sub(/^([A-Za-z]):/, "\\1%3A")
      "sqlite3://#{p}?busy_timeout=5000&foreign_keys=on&journal_mode=wal&synchronous=normal"
    end
  end
end
