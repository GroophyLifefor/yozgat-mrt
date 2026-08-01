require "kemal"
require "sqlite3"
require "crypto/bcrypt"

require "./config"
require "./db/*"
require "./lib/*"
require "./api/*"
require "./app/*"

# Opens the SQLite DB and applies pending migrations before serving.
Yozgat::DB.open!

Kemal.config.port = Yozgat::Config.port
Kemal.config.public_folder = Yozgat::Config.public_dir

Kemal.run
