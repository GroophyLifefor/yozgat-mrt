module Yozgat
  module Deploy
    struct Context
      getter project_id : Int64
      getter environment_id : Int64
      getter deployment_id : Int64
      getter deployment_slug : String
      getter commit_hash : String
      getter assigned_port : Int64
      getter env_slug : String

      def initialize(
        @project_id : Int64,
        @environment_id : Int64,
        @deployment_id : Int64,
        @deployment_slug : String,
        @commit_hash : String,
        @assigned_port : Int64,
        @env_slug : String,
      )
      end
    end
  end
end
