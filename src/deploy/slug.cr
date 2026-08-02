module Yozgat
  module Deploy
    module Slug
      def self.make(deployment_id : Int64) : String
        "#{Time.utc.to_unix}-#{deployment_id}"
      end
    end
  end
end
