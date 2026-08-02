module Yozgat
  # Runtime configuration, env-driven with sensible dev defaults.
  module Config
    @@base_dir : String? = nil
    @@jwt_secret : String? = nil

    def self.port : Int32
      ENV["PORT"]?.try(&.to_i) || 3000
    end

    def self.public_dir : String
      ENV["YOZGAT_PUBLIC_DIR"]? || File.join(Dir.current, "public")
    end

    def self.data_dir : String
      ENV["YOZGAT_DATA_DIR"]? || File.join(Dir.current, "data")
    end

    def self.base_dir : String
      @@base_dir ||= resolve_base_dir(data_dir)
    end

    def self.db_path : String
      File.join(data_dir, "yozgat.db")
    end

    def self.public_ip : String?
      presence(ENV["YOZGAT_PUBLIC_IP"]?)
    end

    # Host used in OpenAPI server URLs and external links.
    def self.server_ip : String
      if ip = public_ip
        ip
      else
        detect_local_ip || "localhost"
      end
    end

    def self.openapi_servers : Array(String)
      ["http://#{server_ip}:#{port}"]
    end

    def self.production? : Bool
      ENV["YOZGAT_ENV"]? == "production"
    end

    def self.jwt_secret : String
      @@jwt_secret ||= begin
        env = ENV["YOZGAT_JWT_SECRET"]?
        if env && !env.empty?
          env
        elsif production?
          raise "YOZGAT_JWT_SECRET must be set when YOZGAT_ENV=production"
        else
          puts "[yozgat] WARN: YOZGAT_JWT_SECRET not set, using ephemeral secret (tokens invalidate on restart)"
          Random::Secure.hex(32)
        end
      end
    end

    # Default base dir: parent of data/ when data_dir ends with "data".
    def self.resolve_base_dir(data_dir : String) : String
      if (env = ENV["YOZGAT_BASE_DIR"]?) && !env.empty?
        return env
      end

      if File.basename(data_dir) == "data"
        File.dirname(data_dir)
      else
        data_dir
      end
    end

    private def self.presence(value : String?) : String?
      return nil unless value
      stripped = value.strip
      stripped.empty? ? nil : stripped
    end

    private def self.detect_local_ip : String?
      socket = UDPSocket.new
      socket.connect("8.8.8.8", 80)
      addr = socket.local_address
      addr.is_a?(Socket::IPAddress) ? addr.address : nil
    rescue
      nil
    ensure
      socket.try(&.close)
    end
  end
end
