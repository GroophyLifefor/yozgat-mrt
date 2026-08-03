require "kemal"
require "sqlite3"
require "ata-validator-crystal"

require "./version"
require "./config"
require "./dns"
require "./db/*"
require "./deploy/*"
require "./traefik/*"
require "./lib/*"
require "./api/*"
require "./app/*"

Dir.mkdir_p(Yozgat::Config.data_dir)
Dir.mkdir_p(Yozgat::Config.base_dir)
Yozgat::Deploy.ensure_runtime_dirs!
Yozgat::Config.ensure_public_ip!

# Opens the SQLite DB, applies migrations, and recovers stale deploy state.
Yozgat::DB.open!
Yozgat::DB.recover_after_restart!

# Registers /openapi.json and /docs (Scalar) routes before Kemal starts.
Yozgat::OpenApi.setup(
  title: "Yozgat API",
  version: Yozgat::VERSION,
  servers: Yozgat::Config.openapi_servers,
)

Kemal.config.port = Yozgat::Config.port
Kemal.config.public_folder = Yozgat::Config.public_dir

Kemal.run
