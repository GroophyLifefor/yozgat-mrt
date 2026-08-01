require "crypto/bcrypt"
require "crypto/subtle"
require "json"
require "openssl/hmac"
require "base64"

module Yozgat
  module Auth
    TOKEN_TTL_SECONDS = 24 * 60 * 60

    alias Claims = NamedTuple(uid: Int64, email: String, role: String)

    def self.hash_password(password : String) : String
      Crypto::Bcrypt.hash_secret(password)
    end

    def self.verify_password(password : String, hash : String) : Bool
      Crypto::Bcrypt::Password.new(hash).verify(password)
    rescue
      false
    end

    # HMAC-signed token: base64url(payload).hex(HMAC-SHA256). Stateless —
    # logout is purely client-side (drop the token).
    def self.sign_token(user_id : Int64, email : String, role : String) : String
      exp = Time.utc.to_unix + TOKEN_TTL_SECONDS
      payload = {uid: user_id, email: email, role: role, exp: exp}.to_json
      encoded = Base64.urlsafe_encode(payload)
      sig = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, Yozgat::Config.jwt_secret, encoded)
      "#{encoded}.#{sig}"
    end

    def self.verify_token(token : String) : Claims?
      parts = token.split('.', 2)
      return nil unless parts.size == 2
      encoded, sig = parts

      expected = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, Yozgat::Config.jwt_secret, encoded)
      return nil unless Crypto::Subtle.constant_time_compare(sig.to_slice, expected.to_slice)

      payload = JSON.parse(Base64.decode_string(encoded))
      exp = payload["exp"]?.try(&.as_i64)
      return nil unless exp && exp > Time.utc.to_unix

      uid = payload["uid"]?.try(&.as_i64)
      email = payload["email"]?.try(&.as_s)
      role = payload["role"]?.try(&.as_s)
      return nil unless uid && email && role

      {uid: uid, email: email, role: role}
    rescue JSON::ParseException
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
      verify_token(token)
    end
  end
end
