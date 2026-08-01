module Yozgat
  module Query
    # env.params.query → JSON string. Değerler string kalır (v1: coercion yok).
    def self.params_to_json(params : HTTP::Params) : String
      params.to_h.to_json
    end
  end
end
