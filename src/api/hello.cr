# JSON API endpoints.

get "/hello" do |env|
  name = env.params.query["name"]? || "world"
  env.response.content_type = "text/plain"
  Yozgat::Helpers.greet(name)
end
