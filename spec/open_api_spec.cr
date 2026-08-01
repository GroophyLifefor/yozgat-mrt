require "./spec_helper"
require "kemal"
require "json"

require "../src/lib/env_ext"
require "../src/lib/query"
require "../src/lib/open_api"
require "../src/lib/api_macro"

Ata.object TaskSpec do
  string :title, min: 1
  int :priority, gt: 0, optional: true
end

api :post, "/tasks",
  body: TaskSpec,
  summary: "Create a task",
  security: ["bearer_auth"],
  responses: {201 => TaskSpec, 400 => TaskSpec} do
  env.status(201).json({ok: true})
end

describe Yozgat::OpenApi do
  it "emits an OpenAPI 3.1 spec with the registered route" do
    Yozgat::OpenApi.setup(title: "Test API", version: "0.0.1")

    json = JSON.parse(Yozgat::OpenApi.spec_json)
    json["openapi"].should eq("3.1.0")
    json["info"]["title"].should eq("Test API")

    op = json["paths"]["/tasks"]["post"]
    op.should be_a(JSON::Any)
    op["summary"].should eq("Create a task")
    op["security"].should eq([{"bearer_auth" => [] of String}])
    op["responses"]["201"].should be_a(JSON::Any)

    body_schema = op["requestBody"]["content"]["application/json"]["schema"]
    body_schema["properties"]["title"]["minLength"].should eq(1)
    body_schema["properties"]["priority"]["exclusiveMinimum"].should eq(0)
  end
end
