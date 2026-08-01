module Yozgat
  # Shared helpers used across api/ and app/ endpoints.
  module Helpers
    def self.greet(name : String) : String
      "Hello #{name}"
    end
  end
end
