# api makrosu — Kemal route tanımı + validasyon + parse + OpenAPI kaydı.
#
#   api :post, "/tasks",
#     body: TaskSchema,
#     summary: "Create a task",
#     security: ["bearer_auth"],
#     responses: {201 => TaskSchema, 400 => ErrorSchema} do
#     task = create_task(body.title)
#     env.status(201).json(task)
#   end
#
# Handler gövdesi route bloğuna splice edilir: `env`, `body`, `query`
# local'leri görür, kapsayıcı local'leri görmez (constant'lar görür).
macro api(method, path, *, body = nil, query = nil,
          summary = nil, tags = [] of String, security = [] of String,
          responses = {} of String => String, &handler)
  {{method.id}} {{path}} do |env|
    {% if body %}
      raw = env.request.body.try(&.gets_to_end) || "{}"
      res = {{body}}.validate(raw)
      unless res.valid
        payload = {error: "validation_error", details: res.errors.map { |e| {path: e.path, message: e.message} }}.to_json
        halt env, status_code: 422, response: payload
      end
      body = {{body}}.from_json(raw)
    {% end %}

    {% if query %}
      qjson = Yozgat::Query.params_to_json(env.params.query)
      res = {{query}}.validate(qjson)
      unless res.valid
        payload = {error: "validation_error", details: res.errors.map { |e| {path: e.path, message: e.message} }}.to_json
        halt env, status_code: 422, response: payload
      end
      query = {{query}}.from_json(qjson)
    {% end %}

    {{handler.body}}
  end

  Yozgat::OpenApi.register(
    method: {{method.id.stringify}},
    path: {{path}},
    summary: {{summary}},
    tags: {{tags}},
    security: {{security}},
    responses: {
      {% for code, schema in responses %}
        {{code}}.to_s => {{schema}}.schema_json,
      {% end %}
    },
    {% if body %}
      body: {{body}}.schema_json,
    {% end %}
  )
end
