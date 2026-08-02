require "crypto/bcrypt"
require "crypto/subtle"
require "digest/sha256"
require "base64"
require "jwt"
require "json"

module Yozgat
  module Auth
    ACCESS_TTL         = 15.minutes
    REFRESH_TTL_SEC    = 30 * 24 * 60 * 60
    REFRESH_RAW_BYTES  = 32

    alias Claims = NamedTuple(sub: String, email: String, role: String)

    def self.hash_password(password : String) : String
      Crypto::Bcrypt.hash_secret(password)
    end

    def self.verify_password(password : String, hash : String) : Bool
      Crypto::Bcrypt::Password.new(hash).verify(password)
    rescue
      false
    end

    def self.sign_access_token(user_id : Int64, email : String, role : String) : String
      payload = {
        "sub"   => user_id.to_s,
        "email" => email,
        "role"  => role,
        "exp"   => (Time.utc + ACCESS_TTL).to_unix,
      }
      JWT.encode(payload, Config.jwt_secret, JWT::Algorithm::HS256)
    end

    def self.verify_access_token(token : String) : Claims?
      payload, _header = JWT.decode(
        token,
        Config.jwt_secret,
        JWT::Algorithm::HS256,
        validate: true,
      )

      sub = payload["sub"]?.try(&.as_s)
      email = payload["email"]?.try(&.as_s)
      role = payload["role"]?.try(&.as_s)
      return nil unless sub && email && role

      {sub: sub, email: email, role: role}
    rescue JWT::Error
      nil
    end

    def self.mint_refresh_token : Tuple(String, String)
      raw = Random::Secure.random_bytes(REFRESH_RAW_BYTES)
      plain = Base64.urlsafe_encode(raw)
      hash = Digest::SHA256.hexdigest(raw)
      {plain, hash}
    end

    def self.hash_refresh_plain(plain : String) : String?
      raw = Base64.decode_string(plain.strip)
      return nil unless raw.bytesize == REFRESH_RAW_BYTES
      Digest::SHA256.hexdigest(raw)
    rescue Base64::Error
      nil
    end

    def self.bearer_token(headers : HTTP::Headers) : String?
      auth = headers["Authorization"]?
      return nil unless auth
      kind, _, value = auth.partition(' ')
      return nil unless kind.downcase == "bearer"
      token = value.strip
      token.empty? ? nil : token
    end

    def self.authenticated(env : HTTP::Server::Context) : Claims?
      return nil unless (token = bearer_token(env.request.headers))
      verify_access_token(token)
    end

    def self.user_agent(headers : HTTP::Headers) : String?
      ua = headers["User-Agent"]?
      return nil unless ua
      ua.size > 512 ? ua[0, 512] : ua
    end
  end
end
