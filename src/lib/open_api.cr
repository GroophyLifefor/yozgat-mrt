module Yozgat
  module OpenApi
    class Operation
      getter method : String, path : String, summary : String?,
              tags : Array(String), security : Array(String),
              responses : Hash(String, String), body : String?

      def initialize(@method, @path, @summary, @tags, @security, @responses, @body = nil); end
    end

    @@operations = [] of Operation
    @@title : String?
    @@version : String?
    @@servers : Array(String) = [] of String

    def self.register(method : String, path : String, summary : String?,
                      tags : Array(String), security : Array(String),
                      responses : Hash(String, String), body : String? = nil) : Nil
      @@operations << Operation.new(method, path, summary, tags, security, responses, body)
    end

    def self.setup(title : String, version : String, servers : Array(String) = [] of String) : Nil
      @@title = title
      @@version = version
      @@servers = servers

      # /openapi.json
      get "/openapi.json" do |env|
        env.response.content_type = "application/json"
        spec_json
      end

      # /docs → Scalar (OpenAPI render)
      get "/docs" do |env|
        env.response.content_type = "text/html"
        scalar_html
      end
    end

    def self.spec_json : String
      String.build do |io|
        JSON.build(io) do |json|
          json.object do
            json.field "openapi", "3.1.0"
            json.field "info" do
              json.object do
                json.field "title", @@title.not_nil!
                json.field "version", @@version.not_nil!
              end
            end
            unless @@servers.empty?
              json.field "servers" do
                json.array do
                  @@servers.each { |u| json.object { json.field "url", u } }
                end
              end
            end
            json.field "components" do
              json.object do
                json.field "securitySchemes" do
                  json.object do
                    json.field "bearer_auth" do
                      json.object do
                        json.field "type", "http"
                        json.field "scheme", "bearer"
                      end
                    end
                  end
                end
              end
            end
            json.field "paths" do
              json.object do
                @@operations.group_by(&.path).each do |path, ops|
                  json.field path do
                    json.object do
                      ops.each do |op|
                        json.field op.method do
                          json.object do
                            json.field "summary", op.summary if op.summary
                            json.field "tags", op.tags unless op.tags.empty?
                            unless op.security.empty?
                              json.field "security" do
                                json.array do
                                  op.security.each do |s|
                                    json.object { json.field s, [] of String }
                                  end
                                end
                              end
                            end
                            if body_json = op.body
                              json.field "requestBody" do
                                json.object do
                                  json.field "content" do
                                    json.object do
                                      json.field "application/json" do
                                        json.object do
                                          json.field "schema", JSON.parse(body_json)
                                        end
                                      end
                                    end
                                  end
                                end
                              end
                            end
                            json.field "responses" do
                              json.object do
                                op.responses.each do |code, schema_json|
                                  json.field code do
                                    json.object do
                                      json.field "description", "HTTP #{code}"
                                      json.field "content" do
                                        json.object do
                                          json.field "application/json" do
                                            json.object do
                                              json.field "schema", JSON.parse(schema_json)
                                            end
                                          end
                                        end
                                      end
                                    end
                                  end
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    # Scalar CDN embed — openapi.json'u render eder.
    def self.scalar_html : String
      <<-HTML
      <!doctype html>
      <html>
      <head>
        <title>Yozgat API</title>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <style>
          body { margin: 0; }
        </style>
      </head>
      <body>
        <script id="api-reference" data-url="/openapi.json"></script>
        <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
      </body>
      </html>
      HTML
    end
  end
end
