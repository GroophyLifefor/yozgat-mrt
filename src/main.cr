require "kemal"
require "sqlite3"
require "ata-validator-crystal"

require "./config"
require "./db/*"
require "./lib/*"
require "./api/*"
require "./app/*"

# Opens the SQLite DB and applies pending migrations before serving.
Yozgat::DB.open!

# Registers /openapi.json and /docs (Scalar) routes before Kemal starts.
Yozgat::OpenApi.setup(
  title: "Yozgat API",
  version: "1.0.0",
  servers: ["http://localhost:#{Yozgat::Config.port}"],
)

Kemal.config.port = Yozgat::Config.port
Kemal.config.public_folder = Yozgat::Config.public_dir

Kemal.run
