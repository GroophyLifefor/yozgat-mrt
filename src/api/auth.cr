require "json"

module Yozgat
  module API
    module Auth
      def self.setup_status(env)
        json_ok(env, {needs_setup: Yozgat::DB.count_users == 0})
      end

      def self.register(env)
        body = parse_body(env)
        return json_error(env, 400, "invalid JSON body") unless body

        email = body_str(body, "email").strip.downcase
        password = body_str(body, "password")
        verify = body_str(body, "verifyPassword")

        if !email_valid?(email)
          return json_error(env, 400, "a valid email is required")
        end
        if password.size < 8
          return json_error(env, 400, "password must be at least 8 characters")
        end
        if password.bytesize > 72
          return json_error(env, 400, "password is too long")
        end
        if password != verify
          return json_error(env, 400, "passwords do not match")
        end

        hash = Yozgat::Auth.hash_password(password)
        if (id = Yozgat::DB.create_admin(email, hash))
          json_ok(env, session_payload(id, email, "admin"))
        else
          json_error(env, 409, "an admin account already exists")
        end
      end

      def self.login(env)
        body = parse_body(env)
        return json_error(env, 400, "invalid JSON body") unless body

        email = body_str(body, "email").strip.downcase
        password = body_str(body, "password")

        if email.empty? || password.empty?
          return json_error(env, 400, "email and password are required")
        end

        user = Yozgat::DB.find_user_by_email(email)
        if user && Yozgat::Auth.verify_password(password, user[:password_hash])
          json_ok(env, session_payload(user[:id], user[:email], user[:role]))
        else
          json_error(env, 401, "invalid email or password")
        end
      end

      def self.me(env)
        claims = Yozgat::Auth.authenticated(env)
        return json_error(env, 401, "unauthorized") unless claims

        user = Yozgat::DB.find_user_by_id(claims[:uid])
        return json_error(env, 401, "unauthorized") unless user

        json_ok(env, {user: user_payload(user)})
      end

      # ── helpers ─────────────────────────────────────────────

      private def self.session_payload(id : Int64, email : String, role : String)
        {
          token:     Yozgat::Auth.sign_token(id, email, role),
          expiresAt: Yozgat::Auth::TOKEN_TTL_SECONDS,
          user:      {id: id, email: email, role: role},
        }
      end

      private def self.user_payload(user : Yozgat::DB::UserRow)
        {id: user[:id], email: user[:email], role: user[:role]}
      end

      private def self.json_ok(env, data)
        env.response.content_type = "application/json"
        data.to_json
      end

      private def self.json_error(env, status : Int32, message : String)
        env.response.status_code = status
        env.response.content_type = "application/json"
        {error: message}.to_json
      end

      private def self.parse_body(env) : Hash(String, JSON::Any)?
        body = env.request.body
        return nil unless body
        JSON.parse(body.gets_to_end).as_h?
      rescue JSON::ParseException
        nil
      end

      private def self.body_str(body : Hash(String, JSON::Any), key : String) : String
        (body[key]?.try(&.as_s?) || "").to_s
      end

      private def self.email_valid?(email : String) : Bool
        return false unless email.includes?('@')
        local, domain = email.split('@', 2)
        !local.empty? && domain.includes?('.') && !domain.starts_with?('.')
      end
    end
  end
end

# ── Routes ──────────────────────────────────────────────────────

get "/setup-status" do |env|
  Yozgat::API::Auth.setup_status(env)
end

post "/auth/register" do |env|
  Yozgat::API::Auth.register(env)
end

post "/auth/login" do |env|
  Yozgat::API::Auth.login(env)
end

get "/auth/me" do |env|
  Yozgat::API::Auth.me(env)
end
