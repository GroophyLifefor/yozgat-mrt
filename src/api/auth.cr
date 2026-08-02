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
          issue_session(env, id, email, "admin")
        else
          env.status(409).json({error: "an admin account already exists"})
        end
      end

      def self.login(env, body : LoginBody)
        email = body.email.strip.downcase
        password = body.password

        return env.status(400).json({error: "email and password are required"}) if email.empty? || password.empty?

        user = Yozgat::DB.find_user_by_email(email)
        unless user && Yozgat::Auth.verify_password(password, user[:password_hash])
          return env.status(401).json({error: "invalid email or password"})
        end

        issue_session(env, user[:id], user[:email], user[:role])
      end

      def self.refresh(env, body : RefreshBody)
        plain = body.refreshToken.strip
        return env.status(400).json({error: "refresh token is required"}) if plain.empty?

        token_hash = Yozgat::Auth.hash_refresh_plain(plain)
        return env.status(401).json({error: "invalid or expired refresh token"}) unless token_hash

        row = Yozgat::DB::RefreshTokens.find_active(token_hash)
        return env.status(401).json({error: "invalid or expired refresh token"}) unless row

        ua = Yozgat::Auth.user_agent(env.request.headers)
        new_plain, new_hash = Yozgat::Auth.mint_refresh_token

        Yozgat::DB.database.transaction do |tx|
          Yozgat::DB::RefreshTokens.rotate!(tx, row[:id], row[:user_id], new_hash, ua)
        end

        env.status(200).json(session_json(
          row[:user_id],
          row[:email],
          row[:role],
          Yozgat::Auth.sign_access_token(row[:user_id], row[:email], row[:role]),
          new_plain,
        ))
      rescue ex
        env.status(500).json({error: ex.message})
      end

      def self.logout(env, body : RefreshBody)
        plain = body.refreshToken.strip
        return env.status(400).json({error: "refresh token is required"}) if plain.empty?

        token_hash = Yozgat::Auth.hash_refresh_plain(plain)
        return env.status(401).json({error: "invalid refresh token"}) unless token_hash

        Yozgat::DB::RefreshTokens.revoke_by_hash(token_hash)
        env.status(200).json({ok: true})
      end

      def self.logout_all(env)
        claims = Yozgat::Auth.authenticated(env)
        return env.status(401).json({error: "unauthorized"}) unless claims

        user_id = claims[:sub].to_i64?
        return env.status(401).json({error: "invalid token payload"}) unless user_id

        Yozgat::DB::RefreshTokens.revoke_all_for_user(user_id)
        env.status(200).json({ok: true})
      end

      def self.me(env)
        claims = Yozgat::Auth.authenticated(env)
        return env.status(401).json({error: "unauthorized"}) unless claims

        user_id = claims[:sub].to_i64?
        return env.status(401).json({error: "unauthorized"}) unless user_id

        user = Yozgat::DB.find_user_by_id(user_id)
        return env.status(401).json({error: "unauthorized"}) unless user

        env.status(200).json({user: user_payload(user)})
      end

      # ── helpers ─────────────────────────────────────────────

      private def self.issue_session(env, id : Int64, email : String, role : String)
        ua = Yozgat::Auth.user_agent(env.request.headers)
        plain, hash = Yozgat::Auth.mint_refresh_token
        Yozgat::DB::RefreshTokens.insert(id, hash, ua)
        access = Yozgat::Auth.sign_access_token(id, email, role)
        env.status(200).json(session_json(id, email, role, access, plain))
      end

      private def self.session_json(
        id : Int64,
        email : String,
        role : String,
        access : String,
        refresh : String,
      )
        {
          accessToken:       access,
          refreshToken:      refresh,
          accessExpiresIn:   Yozgat::Auth::ACCESS_TTL.to_i,
          refreshExpiresIn:  Yozgat::Auth::REFRESH_TTL_SEC,
          tokenType:         "Bearer",
          user:              {id: id, email: email, role: role},
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

Ata.object RefreshBody do
  string :refreshToken, min: 1
end

Ata.object ErrorBody do
  string :error, min: 1
end

Ata.object SetupStatusBody do
  bool :needs_setup
end

Ata.object UserBody do
  int :id
  string :email
  string :role
end

Ata.object SessionBody do
  string :accessToken, min: 1
  string :refreshToken, min: 1
  int :accessExpiresIn
  int :refreshExpiresIn
  string :tokenType, min: 1
  object :user, of: UserBody
end

Ata.object MeBody do
  object :user, of: UserBody
end

Ata.object OkBody do
  bool :ok
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
  responses: {200 => SessionBody, 400 => ErrorBody, 409 => ErrorBody} do
  Yozgat::API::Auth.register(env, body)
end

api :post, "/auth/login",
  body: LoginBody,
  summary: "Log in and receive access + refresh tokens",
  tags: ["auth"],
  responses: {200 => SessionBody, 400 => ErrorBody, 401 => ErrorBody} do
  Yozgat::API::Auth.login(env, body)
end

api :post, "/auth/refresh",
  body: RefreshBody,
  summary: "Rotate refresh token and issue a new access token",
  tags: ["auth"],
  responses: {200 => SessionBody, 400 => ErrorBody, 401 => ErrorBody} do
  Yozgat::API::Auth.refresh(env, body)
end

api :post, "/auth/logout",
  body: RefreshBody,
  summary: "Revoke the current refresh token",
  tags: ["auth"],
  responses: {200 => OkBody, 400 => ErrorBody, 401 => ErrorBody} do
  Yozgat::API::Auth.logout(env, body)
end

api :post, "/auth/logout-all",
  summary: "Revoke all refresh tokens for the authenticated user",
  tags: ["auth"],
  security: ["bearer_auth"],
  responses: {200 => OkBody, 401 => ErrorBody} do
  Yozgat::API::Auth.logout_all(env)
end

api :get, "/auth/me",
  summary: "Current user info",
  tags: ["auth"],
  security: ["bearer_auth"],
  responses: {200 => MeBody, 401 => ErrorBody} do
  Yozgat::API::Auth.me(env)
end
