require "kemal"
require "sqlite3"
require "ata-validator-crystal"

require "./version"
require "./config"
require "./db/*"
require "./deploy/*"
require "./lib/*"
require "./api/*"
require "./app/*"

Dir.mkdir_p(Yozgat::Config.data_dir)
Dir.mkdir_p(Yozgat::Config.base_dir)
Yozgat::Deploy.ensure_runtime_dirs!

# Opens the SQLite DB, applies migrations, and recovers stale deploy state.
Yozgat::DB.open!
Yozgat::DB.recover_after_restart!

# Registers /openapi.json and /docs (Scalar) routes before Kemal starts.
Yozgat::OpenApi.setup(
  title: "Yozgat API",
  version: Yozgat::VERSION,
  servers: ["http://localhost:#{Yozgat::Config.port}"],
)

Kemal.config.port = Yozgat::Config.port
Kemal.config.public_folder = Yozgat::Config.public_dir

Kemal.run
