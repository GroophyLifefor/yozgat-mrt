require "json"

module Yozgat
  module API
    module Auth
      def self.setup_status(env)
        env.status(200).json({needs_setup: Yozgat::DB.count_users == 0})
      end

      def self.register(env, body : RegisterBody)
        email = body.email.strip.downcase
        password = body.password

        if password.bytesize > 72
          return env.status(400).json({error: "password is too long"})
        end
        if password != body.verifyPassword
          return env.status(400).json({error: "passwords do not match"})
        end

        hash = Yozgat::Auth.hash_password(password)
        if (id = Yozgat::DB.create_admin(email, hash))
          env.status(200).json(session_payload(id, email, "admin"))
        else
          env.status(409).json({error: "an admin account already exists"})
        end
      end

      def self.login(env, body : LoginBody)
        email = body.email.strip.downcase
        password = body.password

        user = Yozgat::DB.find_user_by_email(email)
        if user && Yozgat::Auth.verify_password(password, user[:password_hash])
          env.status(200).json(session_payload(user[:id], user[:email], user[:role]))
        else
          env.status(401).json({error: "invalid email or password"})
        end
      end

      def self.me(env)
        claims = Yozgat::Auth.authenticated(env)
        return env.status(401).json({error: "unauthorized"}) unless claims

        user = Yozgat::DB.find_user_by_id(claims[:uid])
        return env.status(401).json({error: "unauthorized"}) unless user

        env.status(200).json({user: user_payload(user)})
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
    end
  end
end

# ── Schemas ─────────────────────────────────────────────────────

Ata.object RegisterBody do
  string :email, format: "email"
  string :password, min: 8
  string :verifyPassword, min: 8
end

Ata.object LoginBody do
  string :email, format: "email"
  string :password, min: 1
end

Ata.object ErrorBody do
  string :error, min: 1
end

Ata.object SetupStatusBody do
  bool :needs_setup
end

# ── Routes ──────────────────────────────────────────────────────

api :get, "/setup-status",
  summary: "Whether the initial admin account has been created",
  tags: ["auth"],
  responses: {200 => SetupStatusBody} do
  Yozgat::API::Auth.setup_status(env)
end

api :post, "/auth/register",
  body: RegisterBody,
  summary: "Create the initial admin account",
  tags: ["auth"],
  responses: {200 => RegisterBody, 400 => ErrorBody, 409 => ErrorBody} do
  Yozgat::API::Auth.register(env, body)
end

api :post, "/auth/login",
  body: LoginBody,
  summary: "Log in and receive a token",
  tags: ["auth"],
  responses: {200 => LoginBody, 401 => ErrorBody} do
  Yozgat::API::Auth.login(env, body)
end

api :get, "/auth/me",
  summary: "Current user info",
  tags: ["auth"],
  security: ["bearer_auth"],
  responses: {200 => LoginBody, 401 => ErrorBody} do
  Yozgat::API::Auth.me(env)
end
