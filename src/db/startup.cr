module Yozgat
  module DB
    # Marks in-flight deploys/projects as failed after a process restart.
    def self.recover_after_restart! : Nil
      database.exec(
        "UPDATE deployments
           SET status = 'failed'
         WHERE status IN ('pending', 'cloning', 'building', 'starting')",
      )
      database.exec(
        "UPDATE projects
           SET status = 'failed'
         WHERE status IN ('starting', 'deploying')",
      )
    end
  end
end
