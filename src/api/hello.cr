# JSON API endpoints.

Ata.object HelloQuery do
  string :name, min: 1
end

api :get, "/hello",
  query: HelloQuery,
  summary: "Greets a user",
  tags: ["hello"],
  responses: {200 => HelloQuery} do
  env.text("Hello #{query.name}")
end
