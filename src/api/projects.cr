module Yozgat
  module API
    module Projects
      def self.require_auth(env) : Yozgat::Auth::Claims?
        claims = Yozgat::Auth.authenticated(env)
        env.status(401).json({error: "unauthorized"}) unless claims
        claims
      end

      def self.parse_id(env, param : String = "id") : Int64?
        raw = env.params.url[param]?
        return nil unless raw
        id = raw.to_i64?
        id && id > 0 ? id : nil
      end

      def self.list(env)
        return unless require_auth(env)

        env.status(200).json({projects: Yozgat::DB::Projects.list})
      end

      def self.create(env, body : CreateProjectBody)
        return unless require_auth(env)

        name = body.name.strip
        return env.status(400).json({error: "name is required"}) if name.empty?

        ptype = Yozgat::DB::Projects.validate_project_type(body.projectType)
        return env.status(400).json({error: "projectType must be static, dockerfile, or dockercompose"}) unless ptype

        repo_url = begin
          Yozgat::Deploy::Git.normalize_github_url(body.repoUrl)
        rescue ex : ArgumentError
          return env.status(400).json({error: ex.message})
        end

        auth_user = trim_opt(body.authUsername)
        auth_token = trim_opt(body.authToken)
        unless (auth_user.nil? && auth_token.nil?) || (auth_user && auth_token)
          return env.status(400).json({error: "authUsername and authToken must both be provided or both omitted"})
        end

        secret = Yozgat::DB::Projects.mint_webhook_secret
        project = Yozgat::DB::Projects.create(name, repo_url, ptype, auth_user, auth_token, secret)
        env.status(201).json({project: project})
      rescue ex
        env.status(500).json({error: ex.message})
      end

      def self.get(env)
        return unless require_auth(env)
        id = parse_id(env)
        return env.status(400).json({error: "invalid project id"}) unless id

        project = Yozgat::DB::Projects.find(id)
        return env.status(404).json({error: "project not found"}) unless project

        env.status(200).json({project: project})
      end

      def self.delete(env)
        return unless require_auth(env)
        id = parse_id(env)
        return env.status(400).json({error: "invalid project id"}) unless id

        return env.status(404).json({error: "project not found"}) unless Yozgat::DB::Projects.delete(id)

        env.status(200).json({ok: true})
      rescue ex
        env.status(500).json({error: ex.message})
      end

      def self.check_repo(env, body : CheckRepoBody)
        return unless require_auth(env)

        normalized = begin
          Yozgat::Deploy::Git.normalize_github_url(body.repoUrl)
        rescue ex : ArgumentError
          return env.status(400).json({error: ex.message})
        end

        is_public = Yozgat::Deploy::Git.ls_remote_success?(normalized)
        env.status(200).json({isPublic: is_public, normalizedUrl: normalized})
      end

      def self.resolve_commit(env, query : ResolveCommitQuery)
        return unless require_auth(env)
        id = parse_id(env)
        return env.status(400).json({error: "invalid project id"}) unless id

        branch = (query.branch || "main").strip
        return env.status(400).json({error: "invalid branch name"}) unless Yozgat::Deploy::Git.branch_ref_ok?(branch)

        creds = Yozgat::DB::Projects.auth_creds(id)
        return env.status(404).json({error: "project not found"}) unless creds

        url = Yozgat::Deploy::Git.authenticated_url(
          creds[:repoUrl],
          creds[:authUsername],
          creds[:authToken],
        )

        hash = Yozgat::Deploy::Git.resolve_branch_head(url, branch)
        env.status(200).json({commitHash: hash, branch: branch})
      rescue ex : ArgumentError
        env.status(502).json({error: ex.message})
      end

      private def self.trim_opt(value : String?) : String?
        return nil unless value
        s = value.strip
        s.empty? ? nil : s
      end
    end
  end
end

# ── Schemas ─────────────────────────────────────────────────────

Ata.object CheckRepoBody do
  string :repoUrl, min: 1
end

Ata.object CheckRepoResponse do
  bool :isPublic
  string :normalizedUrl, min: 1
end

Ata.object CreateProjectBody do
  string :name, min: 1
  string :repoUrl, min: 1
  string :projectType, min: 1
  string :authUsername, optional: true
  string :authToken, optional: true
end

Ata.object ProjectListItem do
  int :id
  string :name, min: 1
  string :repoUrl, min: 1
  string :projectType, min: 1
  string :status, min: 1
  bool :hasPrivateCredentials
  string :createdAt, min: 1
end

Ata.object ProjectDetail do
  int :id
  string :name, min: 1
  string :repoUrl, min: 1
  string :projectType, min: 1
  string :status, min: 1
  bool :hasPrivateCredentials
  string :webhookSecret, min: 1
  string :createdAt, min: 1
end

Ata.object ProjectListResponse do
  array :projects, of: ProjectListItem
end

Ata.object ProjectResponse do
  object :project, of: ProjectListItem
end

Ata.object ProjectDetailResponse do
  object :project, of: ProjectDetail
end

Ata.object ResolveCommitQuery do
  string :branch, optional: true
end

Ata.object ResolveCommitResponse do
  string :commitHash, min: 7
  string :branch, min: 1
end

# ── Routes ──────────────────────────────────────────────────────

api :get, "/projects",
  summary: "List all projects",
  tags: ["projects"],
  security: ["bearer_auth"],
  responses: {200 => ProjectListResponse, 401 => ErrorBody} do
  Yozgat::API::Projects.list(env)
end

api :post, "/projects",
  body: CreateProjectBody,
  summary: "Create a project (seeds a prod environment)",
  tags: ["projects"],
  security: ["bearer_auth"],
  responses: {201 => ProjectResponse, 400 => ErrorBody, 401 => ErrorBody} do
  Yozgat::API::Projects.create(env, body)
end

api :post, "/projects/check-repo",
  body: CheckRepoBody,
  summary: "Check whether a GitHub repo is publicly accessible",
  tags: ["projects"],
  security: ["bearer_auth"],
  responses: {200 => CheckRepoResponse, 400 => ErrorBody, 401 => ErrorBody} do
  Yozgat::API::Projects.check_repo(env, body)
end

api :get, "/projects/:id",
  summary: "Get project details including webhook secret",
  tags: ["projects"],
  security: ["bearer_auth"],
  responses: {200 => ProjectDetailResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::Projects.get(env)
end

api :delete, "/projects/:id",
  summary: "Delete a project and its on-disk data",
  tags: ["projects"],
  security: ["bearer_auth"],
  responses: {200 => OkBody, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody} do
  Yozgat::API::Projects.delete(env)
end

api :get, "/projects/:id/resolve-commit",
  query: ResolveCommitQuery,
  summary: "Resolve a branch name to its HEAD commit hash",
  tags: ["projects"],
  security: ["bearer_auth"],
  responses: {200 => ResolveCommitResponse, 400 => ErrorBody, 401 => ErrorBody, 404 => ErrorBody, 502 => ErrorBody} do
  Yozgat::API::Projects.resolve_commit(env, query)
end
