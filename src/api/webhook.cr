require "openssl/hmac"
require "crypto/subtle"

module Yozgat
  module API
    module Webhook
      def self.deploy(env)
        project_id = Projects.parse_id(env)
        env_slug = env.params.url["env_slug"]?.try(&.strip) || ""

        return env.status(400).json({error: "invalid project id"}) unless project_id
        unless !env_slug.empty? && DB::Environments.slug_ok?(env_slug)
          return env.status(400).json({error: "invalid environment slug"})
        end

        signature = env.request.headers["X-Hub-Signature-256"]? ||
                    env.request.headers["X-Yozgat-Signature-256"]? || ""
        signature = signature.strip
        return env.status(401).json({error: "missing webhook signature"}) if signature.empty?

        body = env.request.body.try(&.gets_to_end) || ""

        secret = DB::Projects.fetch_webhook_secret(project_id)
        return env.status(404).json({error: "project not found"}) unless secret

        unless verify_signature(secret, body, signature)
          return env.status(401).json({error: "invalid webhook signature"})
        end

        commit_hash = parse_commit_hash(body)
        return env.status(400).json({error: "invalid commit hash"}) unless commit_hash

        env_id = DB::Environments.find_id_by_slug(project_id, env_slug)
        return env.status(404).json({error: "environment not found"}) unless env_id

        begin
          ctx = Deploy.start(project_id, env_id, commit_hash)
        rescue ex : ArgumentError
          msg = ex.message || "invalid request"
          status = case msg
                   when "environment not found"    then 404
                   when "project not found"       then 404
                   when "unsupported project type" then 400
                   when "invalid commit hash"      then 400
                   else                              400
                   end
          return env.status(status).json({error: msg})
        end

        deployment = DB::Deployments.find(project_id, env_id, ctx.deployment_id)
        return env.status(500).json({error: "deployment record missing"}) unless deployment

        env.status(200).json({deployment: deployment})
      rescue ex
        env.status(500).json({error: ex.message})
      end

      def self.verify_signature(secret : String, body : String, signature_header : String) : Bool
        provided = signature_header.sub(/^sha256=/i, "").strip
        return false if provided.empty?

        provided_bytes = provided.hexbytes?
        return false unless provided_bytes

        computed = OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, secret, body)
        return false unless computed.size == provided_bytes.size

        Crypto::Subtle.constant_time_compare(computed, provided_bytes)
      rescue
        false
      end

      def self.parse_commit_hash(body : String) : String?
        return nil if body.strip.empty?

        json = JSON.parse(body)

        if (raw = json["commitHash"]?)
          hash = raw.as_s.strip
          return hash if DB::Deployments.commit_hash_ok?(hash)
        end

        if (raw = json["after"]?)
          hash = raw.as_s.strip
          return hash if DB::Deployments.commit_hash_ok?(hash)
        end

        nil
      rescue JSON::Error
        nil
      end
    end
  end
end

# ── Schemas ─────────────────────────────────────────────────────

Ata.object WebhookDeployBody do
  string :commitHash, min: 7, optional: true
end

# ── Route (raw body — not via api macro) ────────────────────────

post "/projects/:id/environments/:env_slug/deploy" do |env|
  Yozgat::API::Webhook.deploy(env)
end

Yozgat::OpenApi.register(
  method: "post",
  path: "/projects/:id/environments/:env_slug/deploy",
  summary: "Webhook-triggered deploy for an environment",
  tags: ["webhooks"],
  security: [] of String,
  responses: {
    "200" => DeploymentResponse.schema_json,
    "400" => ErrorBody.schema_json,
    "401" => ErrorBody.schema_json,
    "404" => ErrorBody.schema_json,
    "500" => ErrorBody.schema_json,
  },
  body: WebhookDeployBody.schema_json,
)
