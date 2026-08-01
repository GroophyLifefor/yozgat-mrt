module Yozgat
  # Runtime configuration, env-driven with sensible dev defaults.
  module Config
    def self.port : Int32
      ENV["PORT"]?.try(&.to_i) || 3000
    end

    def self.public_dir : String
      ENV["YOZGAT_PUBLIC_DIR"]? || File.join(Dir.current, "public")
    end

    def self.data_dir : String
      ENV["YOZGAT_DATA_DIR"]? || File.join(Dir.current, "data")
    end

    def self.db_path : String
      File.join(data_dir, "yozgat.db")
    end

    def self.jwt_secret : String
      @@jwt_secret ||= begin
        if (env = ENV["YOZGAT_JWT_SECRET"]?) && !env.empty?
          env
        else
          puts "[yozgat] WARN: YOZGAT_JWT_SECRET not set, using ephemeral secret (tokens invalidate on restart)"
          Random::Secure.hex(32)
        end
      end
    end
  end
end
