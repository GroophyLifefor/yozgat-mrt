# Response helper'lar — Kemal route bloğunun dönüş değerini yazar, bu yüzden
# metotlar String döndürür. `env.response.print` ile birlikte kullanma
# ("already wrote response" hatası çıkar).
require "json"

class HTTP::Server::Context
  # env.status(404).text("...") — zincir için self döner
  def status(code : Int32) : self
    response.status_code = code
    self
  end

  def text(content : String) : String
    response.content_type = "text/plain"
    content
  end

  def json(content) : String
    response.content_type = "application/json"
    content.to_json
  end
end
